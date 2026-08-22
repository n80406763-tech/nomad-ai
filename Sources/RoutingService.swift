import Foundation
import CoreLocation

final class RoutingService {
    static let shared = RoutingService()

    struct RouteResult: Identifiable {
        let id = UUID()
        var label: String = "Офлайн направление"
        let polyline: [CLLocationCoordinate2D]
        let distanceKm: Double
        let durationMin: Double
        /// true, если это прямая линия между точками (граф трасс недоступен/не покрывает регион),
        /// а не настоящий маршрут по дорогам.
        var isStraightLineFallback: Bool = true
    }

    func buildRoute(waypoints: [CLLocationCoordinate2D]) async throws -> RouteResult {
        guard waypoints.count >= 2 else {
            throw NSError(domain: "RoutingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Нужно минимум две точки"])
        }
        return await buildRoadAwareRoute(waypoints: waypoints)
    }

    func buildAlternatives(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        maxCount: Int = 1,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> [RouteResult] {
        _ = maxCount
        onProgress?(0, 1)
        let route = await buildRoadAwareRoute(waypoints: [from, to])
        onProgress?(1, 1)
        return [route]
    }

    /// Строит маршрут по офлайн-графу федеральных трасс между всеми точками по очереди.
    /// Если граф недоступен или не покрывает какой-то из участков (снап дальше допустимого
    /// радиуса от известной трассы), честно откатывается на прямую линию для всего маршрута.
    func buildRoadAwareRoute(waypoints: [CLLocationCoordinate2D]) async -> RouteResult {
        guard waypoints.count >= 2 else {
            return buildOfflineRoute(waypoints: waypoints)
        }

        var polyline: [CLLocationCoordinate2D] = [waypoints[0]]
        var totalMeters = 0.0
        var totalSeconds = 0.0

        for index in 0..<(waypoints.count - 1) {
            guard let leg = await OfflineRoadGraph.shared.route(from: waypoints[index], to: waypoints[index + 1]) else {
                return buildOfflineRoute(waypoints: waypoints)
            }
            polyline.append(contentsOf: leg.polyline.dropFirst())
            totalMeters += leg.distanceMeters
            totalSeconds += leg.durationSeconds
        }

        return RouteResult(
            label: "Маршрут по трассам (офлайн)",
            polyline: polyline,
            distanceKm: totalMeters / 1000.0,
            durationMin: totalSeconds / 60.0,
            isStraightLineFallback: false
        )
    }

    func buildOfflineRoute(waypoints: [CLLocationCoordinate2D]) -> RouteResult {
        guard waypoints.count >= 2 else {
            return RouteResult(polyline: waypoints, distanceKm: 0, durationMin: 0)
        }

        var totalDistance = 0.0
        for index in 0..<(waypoints.count - 1) {
            let start = CLLocation(latitude: waypoints[index].latitude, longitude: waypoints[index].longitude)
            let end = CLLocation(latitude: waypoints[index + 1].latitude, longitude: waypoints[index + 1].longitude)
            totalDistance += start.distance(from: end)
        }

        return RouteResult(
            label: "Офлайн направление",
            polyline: waypoints,
            distanceKm: totalDistance / 1000.0,
            durationMin: totalDistance / 1000.0 / 80.0 * 60.0
        )
    }
}
