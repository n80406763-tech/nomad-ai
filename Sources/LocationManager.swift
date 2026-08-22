import Foundation
import CoreLocation
import Combine
import UIKit

struct LocationDiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

/// Центральный менеджер GPS с фильтрацией шума и работой в фоне.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var speed: Double = 0            // км/ч
    @Published var accuracy: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var lastRawAccuracy: Double?
    @Published var lastLocationTimestamp: Date?
    @Published var lastErrorMessage: String?
    @Published private(set) var diagnosticEvents: [LocationDiagnosticEvent] = []
    /// true, когда GPS-фикс давно не обновлялся и на карте показана последняя известная точка
    /// (позицию НЕ выдумываем — просто держим на месте, как это делают Яндекс/Google).
    @Published private(set) var isSignalStale = false

    // Защита от GPS-прыжков: буфер последних точек
    private var locationBuffer: [CLLocation] = []
    private let bufferSize = 5
    private var hasLoggedFirstLocation = false
    private var lastWeakSignalDiagnostic = Date.distantPast
    private var updatesReceived = 0

    private var lastRealLocation: CLLocation?
    private var staleCheckTimer: Timer?
    /// Насколько давно GPS-фикс не обновлялся, прежде чем считать сигнал потерянным.
    /// Держим с запасом: на месте машина/телефон тоже могут не слать частых обновлений.
    private static let staleThreshold: TimeInterval = 12

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        // kCLDistanceFilterNone: получать все обновления, даже стоя на месте.
        // При distanceFilter>0 неподвижность выглядит как «нет сигнала» — а именно это
        // раньше ошибочно запускало счисление пути и уводило точку на километры.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 5                // обновляем при повороте > 5°
        authorizationStatus = manager.authorizationStatus
        recordDiagnostic("Инициализация: службы геолокации \(CLLocationManager.locationServicesEnabled() ? "включены" : "выключены"), доступ: \(authorizationDescription).")
    }

    var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "не запрошен"
        case .restricted: return "ограничен системой"
        case .denied: return "запрещён"
        case .authorizedAlways: return "разрешён всегда"
        case .authorizedWhenInUse: return "разрешён при использовании"
        @unknown default: return "неизвестен"
        }
    }

    var accuracyAuthorizationDescription: String {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return "нет доступа"
        }
        return manager.accuracyAuthorization == .fullAccuracy ? "точная" : "приблизительная"
    }

    var latestLocationDescription: String {
        guard let lastLocationTimestamp else { return "координаты ещё не получены" }
        let age = max(0, Int(Date().timeIntervalSince(lastLocationTimestamp)))
        if let lastRawAccuracy {
            return "±\(Int(lastRawAccuracy)) м, \(age) с назад"
        }
        return "\(age) с назад"
    }

    func requestPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            reportLocationServicesDisabled()
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            recordDiagnostic("Запрошено разрешение на геолокацию при использовании приложения.")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startTracking()
        case .denied, .restricted:
            reportLocationAccessDenied()
        @unknown default:
            break
        }
    }

    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Навигатору нужна полная точность. Если пользователь дал доступ в режиме
    /// «Приблизительно» (iOS 14+), позиция приходит с точностью ~1–5 км и почти
    /// не обновляется при движении — просим временно поднять до точной.
    /// Требует ключ NSLocationTemporaryUsageDescriptionDictionary → "navigation" в Info.plist.
    private func ensureFullAccuracy() {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return }
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        recordDiagnostic("Доступ выдан в режиме «Приблизительно» — запрашиваю точное местоположение для навигации.")
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "navigation") { [weak self] error in
            guard let self else { return }
            if let error {
                self.recordDiagnostic("Не удалось поднять точность GPS: \(error.localizedDescription)")
            }
            self.recordDiagnostic("Точность GPS: \(self.accuracyAuthorizationDescription).")
            if self.manager.accuracyAuthorization == .reducedAccuracy {
                Task { @MainActor in
                    DiagnosticsStore.shared.report(
                        title: "Включите «Точное местоположение»",
                        details: "Сейчас доступ выдан приблизительно (±несколько км), позиция не двигается. Настройки → Nomad → Геопозиция → включите «Точное местоположение»."
                    )
                }
            }
        }
    }

    func startTracking() {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return }
        if !isTracking {
            recordDiagnostic("Запущено получение координат и направления.")
        }
        ensureFullAccuracy()
        // Мгновенно показываем последнюю известную позицию из кэша iOS, пока ищем свежий фикс —
        // так карта не пустует первые секунды (именно это делает Яндекс/Google: сразу
        // рисуют точку из кэша, а затем уточняют её). Свежий фикс из didUpdateLocations
        // тут же перезапишет это значение.
        if location == nil, let cached = manager.location, cached.horizontalAccuracy >= 0,
           -cached.timestamp.timeIntervalSinceNow < 300 {
            location = cached
            accuracy = cached.horizontalAccuracy
            speed = max(0, cached.speed) * 3.6
            lastRealLocation = cached
            recordDiagnostic("Показана последняя известная позиция из кэша (±\(Int(cached.horizontalAccuracy)) м), ищу свежий сигнал.")
        }
        // Разрешаем фоновые обновления (в Info.plist объявлен режим location) —
        // без этого iOS может «засыпать» поток координат.
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
        startStaleCheckTimer()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
        staleCheckTimer?.invalidate()
        staleCheckTimer = nil
        isSignalStale = false
        recordDiagnostic("Получение координат остановлено.")
    }

    /// Раз в секунду проверяет, давно ли обновлялся GPS. Если сигнал потерян —
    /// только помечаем это флагом для HUD, НЕ трогая саму точку: карта показывает
    /// последнюю известную позицию на месте (позицию не выдумываем).
    private func startStaleCheckTimer() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.evaluateSignalFreshness()
        }
    }

    private func evaluateSignalFreshness() {
        guard isTracking, let lastReal = lastRealLocation else { return }
        let age = -lastReal.timestamp.timeIntervalSinceNow
        let stale = age > Self.staleThreshold
        guard stale != isSignalStale else { return }
        isSignalStale = stale
        recordDiagnostic(stale
            ? "GPS-сигнал не обновлялся \(Int(age)) с — показываю последнюю известную позицию."
            : "GPS-сигнал снова обновляется.")
    }

    func clearDiagnostics() {
        diagnosticEvents = []
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let raw = locations.last else {
            recordDiagnostic("Core Location не передал координаты.")
            return
        }

        let age = -raw.timestamp.timeIntervalSinceNow
        publishSignalMetadata(raw)
        guard age < 30 else {
            recordDiagnostic("Отклонена устаревшая координата: \(Int(age)) с.")
            return
        }

        guard raw.horizontalAccuracy >= 0 else {
            recordDiagnostic("Core Location сообщил недействительную точность GPS.")
            return
        }

        guard raw.horizontalAccuracy <= 10_000 else {
            recordWeakSignal("Точность GPS пока слишком низкая: ±\(Int(raw.horizontalAccuracy)) м.")
            return
        }

        let displayedLocation: CLLocation
        if raw.horizontalAccuracy <= 65 {
            locationBuffer.append(raw)
            if locationBuffer.count > bufferSize { locationBuffer.removeFirst() }
            // Сглаживаем шум точностью, но никогда не откатываемся к более старой точке —
            // иначе позиция на карте может "прыгнуть назад" во времени.
            let bestAccuracy = locationBuffer.map(\.horizontalAccuracy).min() ?? raw.horizontalAccuracy
            let acceptableThreshold = bestAccuracy * 1.5
            displayedLocation = locationBuffer.last { $0.horizontalAccuracy <= acceptableThreshold } ?? raw
        } else {
            displayedLocation = raw
            recordWeakSignal("Получен слабый GPS-сигнал: ±\(Int(raw.horizontalAccuracy)) м. Позиция показана, точность будет улучшаться.")
        }

        lastRealLocation = displayedLocation

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.location = displayedLocation
            self.accuracy = displayedLocation.horizontalAccuracy
            self.speed = max(0, displayedLocation.speed) * 3.6
            self.lastErrorMessage = nil
            self.isSignalStale = false
        }

        // Диагностика: первые 8 фиксов логируем всегда — видно, как точность
        // сходится со временем (вышка ±км → Wi-Fi/спутники ±десятки метров).
        if updatesReceived < 8 {
            recordDiagnostic("Фикс #\(updatesReceived + 1): ±\(Int(raw.horizontalAccuracy)) м, скорость \(Int(max(0, raw.speed) * 3.6)) км/ч.")
        }
        updatesReceived += 1

        if !hasLoggedFirstLocation {
            hasLoggedFirstLocation = true
            recordDiagnostic("Получена первая координата: ±\(Int(raw.horizontalAccuracy)) м.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async { self.heading = newHeading }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.recordDiagnostic("Изменился доступ к GPS: \(self.authorizationDescription), точность: \(self.accuracyAuthorizationDescription).")
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.startTracking()
            } else if status == .denied {
                self.reportLocationAccessDenied()
            } else if status == .restricted {
                self.reportLocationServicesDisabled()
            }
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        recordDiagnostic("iPhone временно приостановил обновления геолокации.")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        recordDiagnostic("iPhone возобновил обновления геолокации.")
    }

    private func reportLocationAccessDenied() {
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "GPS отключён",
                details: "Доступ к геолокации уже был запрещён. Откройте Настройки iPhone и разрешите доступ для Nomad."
            )
        }
    }

    private func reportLocationServicesDisabled() {
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "GPS недоступен",
                details: "Включите Службы геолокации в настройках iPhone, затем вернитесь в Nomad."
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorDomain/0 (.locationUnknown) — штатное "пока не вижу спутники, но продолжаю
        // пытаться": CoreLocation сам повторяет попытки и обычно быстро восстанавливается
        // (холодный старт, помещение, слабый сигнал). Ни один настоящий навигатор не
        // показывает это как ошибку пользователю — только тихо логируем.
        if let clError = error as? CLError, clError.code == .locationUnknown {
            recordDiagnostic("Core Location временно не может определить позицию (locationUnknown) — попытки продолжаются.")
            return
        }

        print("[LocationManager] Ошибка GPS: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.lastErrorMessage = error.localizedDescription
        }
        recordDiagnostic("Ошибка Core Location: \(error.localizedDescription)")
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "Ошибка GPS",
                details: error.localizedDescription
            )
        }
    }

    private func publishSignalMetadata(_ location: CLLocation) {
        DispatchQueue.main.async {
            self.lastRawAccuracy = location.horizontalAccuracy
            self.lastLocationTimestamp = location.timestamp
        }
    }

    private func recordWeakSignal(_ message: String) {
        guard Date().timeIntervalSince(lastWeakSignalDiagnostic) > 15 else { return }
        lastWeakSignalDiagnostic = Date()
        recordDiagnostic(message)
    }

    private func recordDiagnostic(_ message: String) {
        print("[Nomad GPS] \(message)")
        let event = LocationDiagnosticEvent(timestamp: Date(), message: message)
        DispatchQueue.main.async {
            self.diagnosticEvents.insert(event, at: 0)
            if self.diagnosticEvents.count > 30 {
                self.diagnosticEvents.removeLast(self.diagnosticEvents.count - 30)
            }
        }
    }
}
