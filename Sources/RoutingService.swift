import Foundation
import CoreLocation

/// Сервис построения маршрута через OSRM (бесплатный, онлайн)
/// При офлайне — просто соединяем waypoints прямыми линиями (заглушка)
final class RoutingService {
    static let shared = RoutingService()

    // OSRM публичный API (без ключа, бесплатный)
    private let baseURL = "https://router.project-osrm.org/route/v1/driving/"

    struct RouteResult {
        let polyline: [CLLocationCoordinate2D]
        let distanceKm: Double
        let durationMin: Double
    }

    /// Строим маршрут через несколько точек онлайн
    func buildRoute(waypoints: [CLLocationCoordinate2D]) async throws -> RouteResult {
        guard waypoints.count >= 2 else {
            throw NSError(domain: "RoutingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Нужно минимум 2 точки"])
        }

        let coordStr = waypoints.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        let urlStr = baseURL + coordStr + "?overview=full&geometries=geojson&alternatives=true"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let routes = json?["routes"] as? [[String: Any]], let first = routes.first else {
            throw NSError(domain: "RoutingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Маршрут не найден"])
        }

        let distance = (first["distance"] as? Double ?? 0) / 1000.0  // км
        let duration = (first["duration"] as? Double ?? 0) / 60.0    // мин

        var coords: [CLLocationCoordinate2D] = []
        if let geometry = first["geometry"] as? [String: Any],
           let coordsRaw = geometry["coordinates"] as? [[Double]] {
            coords = coordsRaw.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        }

        return RouteResult(polyline: coords, distanceKm: distance, durationMin: duration)
    }

    /// Офлайн fallback: прямые линии между точками
    func buildOfflineRoute(waypoints: [CLLocationCoordinate2D]) -> RouteResult {
        var totalDist = 0.0
        for i in 0..<(waypoints.count - 1) {
            let a = CLLocation(latitude: waypoints[i].latitude, longitude: waypoints[i].longitude)
            let b = CLLocation(latitude: waypoints[i+1].latitude, longitude: waypoints[i+1].longitude)
            totalDist += a.distance(from: b)
        }
        return RouteResult(polyline: waypoints, distanceKm: totalDist / 1000.0, durationMin: totalDist / 1000.0 / 80.0 * 60.0)
    }
}
