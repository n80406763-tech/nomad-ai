import Foundation
import CoreLocation

/// Сервис построения маршрута через OSRM (бесплатный, онлайн)
/// При офлайне — просто соединяем waypoints прямыми линиями (заглушка)
final class RoutingService {
    static let shared = RoutingService()

    // OSRM публичный API (без ключа, бесплатный)
    private let baseURL = "https://router.project-osrm.org/route/v1/driving/"

    struct RouteResult: Identifiable {
        let id = UUID()
        var label: String = "Маршрут"
        let polyline: [CLLocationCoordinate2D]
        let distanceKm: Double
        let durationMin: Double
    }

    /// Строим маршрут через несколько точек онлайн
    func buildRoute(waypoints: [CLLocationCoordinate2D]) async throws -> RouteResult {
        let routes = try await requestRoutes(waypoints: waypoints, alternatives: true)
        guard let first = routes.first else {
            throw NSError(domain: "RoutingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Маршрут не найден"])
        }
        return first
    }

    /// Строим до 20 различных вариантов маршрута между двумя точками:
    /// сначала реальные альтернативы OSRM, затем варианты через смещённые
    /// промежуточные точки (реальные, отдельно рассчитанные маршруты, а не подделка).
    /// onProgress вызывается после каждой партии запросов: (сколько уже найдено, сколько всего попыток запланировано)
    func buildAlternatives(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        maxCount: Int = 20,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> [RouteResult] {
        var found: [RouteResult] = []

        if let direct = try? await requestRoutes(waypoints: [from, to], alternatives: true) {
            found.append(contentsOf: direct)
        }
        onProgress?(found.count, maxCount)

        // Смещённые "via" точки по обе стороны прямой линии — дают реальные,
        // но объездные маршруты (через другие дороги/города).
        let mid = CLLocationCoordinate2D(latitude: (from.latitude + to.latitude) / 2, longitude: (from.longitude + to.longitude) / 2)
        let dLat = to.latitude - from.latitude
        let dLon = to.longitude - from.longitude
        let length = max(sqrt(dLat * dLat + dLon * dLon), 0.0001)
        // Перпендикулярное направление к линии маршрута
        let perpLat = -dLon / length
        let perpLon = dLat / length

        let offsets: [Double] = [0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.3, -1.3, 1.8, -1.8]
        let fractions: [Double] = [0.35, 0.5, 0.65]

        var candidateVias: [CLLocationCoordinate2D] = []
        for offset in offsets {
            for fraction in fractions {
                let base = CLLocationCoordinate2D(
                    latitude: from.latitude + dLat * fraction,
                    longitude: from.longitude + dLon * fraction
                )
                let scale = length * offset
                candidateVias.append(CLLocationCoordinate2D(
                    latitude: base.latitude + perpLat * scale,
                    longitude: base.longitude + perpLon * scale
                ))
            }
        }
        _ = mid

        // Ограничиваем число параллельных сетевых запросов, чтобы не перегружать публичный сервер OSRM.
        let neededExtra = max(0, maxCount - found.count)
        if neededExtra > 0 {
            let vias = Array(candidateVias.prefix(neededExtra * 2))
            let chunkSize = 4
            var index = 0
            let totalAttempts = found.count + vias.count
            while index < vias.count && found.count < maxCount {
                let chunk = Array(vias[index..<min(index + chunkSize, vias.count)])
                await withTaskGroup(of: RouteResult?.self) { group in
                    for via in chunk {
                        group.addTask {
                            try? await self.requestRoutes(waypoints: [from, via, to], alternatives: false).first
                        }
                    }
                    for await result in group {
                        if let result { found.append(result) }
                    }
                }
                index += chunkSize
                onProgress?(min(found.count, maxCount), totalAttempts)
            }
        }

        let unique = dedupe(found)
        let sorted = unique.sorted { $0.durationMin < $1.durationMin }
        var labeled = Array(sorted.prefix(maxCount))
        for i in labeled.indices {
            labeled[i].label = "Маршрут \(i + 1)"
        }
        onProgress?(labeled.count, max(labeled.count, 1))
        return labeled
    }

    /// Убираем почти одинаковые маршруты (похожая дистанция и длительность)
    private func dedupe(_ routes: [RouteResult]) -> [RouteResult] {
        var result: [RouteResult] = []
        for route in routes {
            let isDuplicate = result.contains { existing in
                abs(existing.distanceKm - route.distanceKm) < max(existing.distanceKm, 1) * 0.02 &&
                abs(existing.durationMin - route.durationMin) < max(existing.durationMin, 1) * 0.02
            }
            if !isDuplicate { result.append(route) }
        }
        return result
    }

    /// Низкоуровневый запрос к OSRM, возвращает все найденные варианты (routes[])
    private func requestRoutes(waypoints: [CLLocationCoordinate2D], alternatives: Bool) async throws -> [RouteResult] {
        guard waypoints.count >= 2 else {
            throw NSError(domain: "RoutingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Нужно минимум 2 точки"])
        }

        let coordStr = waypoints.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        let urlStr = baseURL + coordStr + "?overview=full&geometries=geojson&alternatives=\(alternatives)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let routes = json?["routes"] as? [[String: Any]], !routes.isEmpty else {
            throw NSError(domain: "RoutingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Маршрут не найден"])
        }

        return routes.compactMap { route -> RouteResult? in
            let distance = (route["distance"] as? Double ?? 0) / 1000.0
            let duration = (route["duration"] as? Double ?? 0) / 60.0
            guard let geometry = route["geometry"] as? [String: Any],
                  let coordsRaw = geometry["coordinates"] as? [[Double]] else { return nil }
            let coords: [CLLocationCoordinate2D] = coordsRaw.compactMap { pair in
                guard pair.count >= 2,
                      pair[0].isFinite,
                      pair[1].isFinite,
                      (-180...180).contains(pair[0]),
                      (-90...90).contains(pair[1]) else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            guard coords.count >= 2 else { return nil }
            return RouteResult(polyline: coords, distanceKm: distance, durationMin: duration)
        }
    }

    /// Офлайн fallback: прямые линии между точками
    func buildOfflineRoute(waypoints: [CLLocationCoordinate2D]) -> RouteResult {
        guard waypoints.count >= 2 else {
            return RouteResult(polyline: waypoints, distanceKm: 0, durationMin: 0)
        }
        var totalDist = 0.0
        for i in 0..<(waypoints.count - 1) {
            let a = CLLocation(latitude: waypoints[i].latitude, longitude: waypoints[i].longitude)
            let b = CLLocation(latitude: waypoints[i+1].latitude, longitude: waypoints[i+1].longitude)
            totalDist += a.distance(from: b)
        }
        return RouteResult(polyline: waypoints, distanceKm: totalDist / 1000.0, durationMin: totalDist / 1000.0 / 80.0 * 60.0)
    }
}
