import Foundation
import CoreLocation
import Combine

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

    // Защита от GPS-прыжков: буфер последних точек
    private var locationBuffer: [CLLocation] = []
    private let bufferSize = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 3               // обновляем каждые 3 метра
        manager.headingFilter = 5                // обновляем при повороте > 5°
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let raw = locations.last else { return }

        // Фильтр 1: Отбрасываем устаревшие точки (старше 5 секунд)
        let age = -raw.timestamp.timeIntervalSinceNow
        guard age < 5 else { return }

        // Фильтр 2: Отбрасываем точки с плохой точностью (> 65 м = ненадежно)
        guard raw.horizontalAccuracy >= 0, raw.horizontalAccuracy <= 65 else { return }

        // Фильтр 3: Медианный фильтр на основе буфера (убирает резкие прыжки GPS)
        locationBuffer.append(raw)
        if locationBuffer.count > bufferSize { locationBuffer.removeFirst() }
        let filtered = locationBuffer.sorted { $0.horizontalAccuracy < $1.horizontalAccuracy }.first ?? raw

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.location = filtered
            self.accuracy = filtered.horizontalAccuracy
            self.speed = max(0, filtered.speed) * 3.6  // m/s -> km/h
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async { self.heading = newHeading }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.startTracking()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Ошибка GPS: \(error.localizedDescription)")
    }
}
