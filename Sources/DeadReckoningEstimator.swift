import CoreLocation
import CoreMotion

/// Кратковременная экстраполяция позиции по гироскопу/акселерометру,
/// когда GPS-сигнал пропадает (тоннель, подземный паркинг, плотная застройка).
/// Не претендует на точность GPS — только на то, чтобы курсор на карте
/// продолжал двигаться разумно, пока сигнал не вернётся, вместо того чтобы
/// замереть или показать устаревшую точку.
final class DeadReckoningEstimator {
    /// Дольше этого без GPS доверять счислению уже нельзя — снос слишком велик.
    static let maxBridgeDuration: TimeInterval = 45

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    private var anchorAccuracy: Double = 0
    private var anchorAltitude: Double = 0
    private var anchorVerticalAccuracy: Double = 0
    private var currentLatRadians: Double = 0
    private var currentLonRadians: Double = 0
    private var headingRadians: Double = 0
    private var speedMS: Double = 0
    private var lastSampleTime: Date?
    private var startedAt: Date?

    private(set) var isRunning = false

    /// Начать счисление от последней достоверной точки GPS.
    func start(from lastGood: CLLocation) {
        guard motionManager.isDeviceMotionAvailable else { return }
        anchorAccuracy = lastGood.horizontalAccuracy
        anchorAltitude = lastGood.altitude
        anchorVerticalAccuracy = lastGood.verticalAccuracy
        currentLatRadians = lastGood.coordinate.latitude * .pi / 180
        currentLonRadians = lastGood.coordinate.longitude * .pi / 180
        headingRadians = (lastGood.course >= 0 ? lastGood.course : 0) * .pi / 180
        speedMS = max(0, lastGood.speed)
        lastSampleTime = Date()
        startedAt = Date()
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] _, _ in
            // Данные читаются по требованию в estimate() — здесь только держим поток обновлений живым.
            _ = self
        }
    }

    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        lastSampleTime = nil
        startedAt = nil
    }

    /// Вычислить текущую предполагаемую точку, на шаг продвинув модель с прошлого вызова.
    /// `nil`, если счисление не запущено или мост по времени уже превышен
    /// (слишком велик снос — честнее показать «нет сигнала»).
    func estimate() -> CLLocation? {
        guard isRunning, let startedAt else { return nil }
        let now = Date()
        let elapsedSinceStart = now.timeIntervalSince(startedAt)
        guard elapsedSinceStart <= Self.maxBridgeDuration else { return nil }

        // Пошагово интегрируем от ПОСЛЕДНЕЙ позиции, а не пересчитываем с нуля от точки старта —
        // иначе повороты курса за время моста игнорировались бы (путь считался бы прямым).
        let dt = now.timeIntervalSince(lastSampleTime ?? now)
        if let motion = motionManager.deviceMotion, dt > 0 {
            // Интегрируем поворот (рысканье) — учитываем повороты во время потери сигнала.
            headingRadians += motion.rotationRate.z * dt
            // Продольное ускорение слегка корректирует скорость, но с сильным затуханием,
            // чтобы шум акселерометра не разгонял/тормозил модель до абсурда.
            let forwardAccel = motion.userAcceleration.y * 9.80665
            speedMS = max(0, min(speedMS + forwardAccel * dt * 0.3, speedMS + 5))
        }
        lastSampleTime = now

        let stepMeters = speedMS * max(0, dt)
        let earthRadius = 6_371_000.0
        let angularDistance = stepMeters / earthRadius

        let newLat = asin(
            sin(currentLatRadians) * cos(angularDistance) +
            cos(currentLatRadians) * sin(angularDistance) * cos(headingRadians)
        )
        let newLon = currentLonRadians + atan2(
            sin(headingRadians) * sin(angularDistance) * cos(currentLatRadians),
            cos(angularDistance) - sin(currentLatRadians) * sin(newLat)
        )
        currentLatRadians = newLat
        currentLonRadians = newLon

        // Точность деградирует со временем — честно отражаем растущую неопределённость.
        let degradedAccuracy = anchorAccuracy + elapsedSinceStart * 6

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: currentLatRadians * 180 / .pi, longitude: currentLonRadians * 180 / .pi),
            altitude: anchorAltitude,
            horizontalAccuracy: degradedAccuracy,
            verticalAccuracy: anchorVerticalAccuracy,
            course: headingRadians * 180 / .pi,
            speed: speedMS,
            timestamp: now
        )
    }
}
