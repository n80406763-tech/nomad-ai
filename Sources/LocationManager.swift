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
    /// true, пока позиция вычисляется счислением пути (гироскоп/акселерометр), а не живым GPS-фиксом.
    @Published private(set) var isDeadReckoning = false

    // Защита от GPS-прыжков: буфер последних точек
    private var locationBuffer: [CLLocation] = []
    private let bufferSize = 5
    private var hasLoggedFirstLocation = false
    private var lastWeakSignalDiagnostic = Date.distantPast

    // Гибридное позиционирование: GPS + счисление пути на время потери сигнала
    private let deadReckoning = DeadReckoningEstimator()
    private var lastRealLocation: CLLocation?
    private var staleCheckTimer: Timer?
    /// Сколько GPS-фикс может "молчать", прежде чем включаем счисление пути.
    private static let staleThreshold: TimeInterval = 4
    private var lastBridgeLostDiagnostic = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 3               // обновляем каждые 3 метра
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

    func startTracking() {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return }
        if !isTracking {
            recordDiagnostic("Запущено получение координат и направления.")
        }
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
        deadReckoning.stop()
        isDeadReckoning = false
        recordDiagnostic("Получение координат остановлено.")
    }

    /// Раз в секунду проверяет, не "молчит" ли GPS дольше порога — если да,
    /// подхватывает позицию гибридным счислением пути (гироскоп + акселерометр),
    /// пока не вернётся настоящий фикс или не истечёт время доверия мосту.
    private func startStaleCheckTimer() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.evaluateBridging()
        }
    }

    private func evaluateBridging() {
        guard isTracking, let lastReal = lastRealLocation else { return }
        let age = -lastReal.timestamp.timeIntervalSinceNow
        guard age > Self.staleThreshold else {
            if deadReckoning.isRunning {
                deadReckoning.stop()
                isDeadReckoning = false
            }
            return
        }

        if !deadReckoning.isRunning {
            deadReckoning.start(from: lastReal)
            recordDiagnostic("GPS-сигнал пропал \(Int(age)) с назад — включено счисление пути по гироскопу.")
        }

        if let estimated = deadReckoning.estimate() {
            location = estimated
            accuracy = estimated.horizontalAccuracy
            speed = max(0, estimated.speed) * 3.6
            isDeadReckoning = true
        } else {
            deadReckoning.stop()
            isDeadReckoning = false
            if Date().timeIntervalSince(lastBridgeLostDiagnostic) > 15 {
                lastBridgeLostDiagnostic = Date()
                recordDiagnostic("Счисление пути превысило время доверия — позиция без GPS больше не показывается.")
            }
        }
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

        // Настоящий фикс важнее оценки счисления пути — как только сигнал вернулся, мост закрывается.
        lastRealLocation = displayedLocation
        if deadReckoning.isRunning {
            deadReckoning.stop()
            recordDiagnostic("GPS-сигнал восстановлен — счисление пути отключено.")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.location = displayedLocation
            self.accuracy = displayedLocation.horizontalAccuracy
            self.speed = max(0, displayedLocation.speed) * 3.6
            self.lastErrorMessage = nil
            self.isDeadReckoning = false
        }

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
