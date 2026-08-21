import Foundation
import CoreLocation

/// Хранилище маршрутов (UserDefaults + JSON)
final class RouteStore: ObservableObject {
    static let shared = RouteStore()
    private let key = "saved_routes_v1"

    @Published var routes: [SavedRoute] = []
    @Published var activeRoute: SavedRoute?

    init() { load() }

    func save(_ route: SavedRoute) {
        routes.removeAll { $0.id == route.id }
        routes.insert(route, at: 0)
        persist()
    }

    func delete(_ route: SavedRoute) {
        routes.removeAll { $0.id == route.id }
        if activeRoute?.id == route.id { activeRoute = nil }
        persist()
    }

    func activate(_ route: SavedRoute) {
        for i in routes.indices { routes[i].isActive = routes[i].id == route.id }
        activeRoute = route
        persist()
    }

    func deactivate() {
        for i in routes.indices { routes[i].isActive = false }
        activeRoute = nil
        persist()
    }

    // MARK: Отклонение от маршрута
    /// Возвращает расстояние в метрах от точки до ближайшей точки активного маршрута
    func distanceFromActiveRoute(location: CLLocation) -> Double? {
        guard let polyline = activeRoute?.polyline, polyline.count > 1 else { return nil }
        var minDist = Double.greatestFiniteMagnitude
        for coord in polyline {
            let pt = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let d = location.distance(from: pt)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    // MARK: Оставшееся расстояние и время
    func remainingDistance(from location: CLLocation) -> Double? {
        guard let polyline = activeRoute?.polyline, polyline.count > 1 else { return nil }
        // Найти ближайшую точку и посчитать расстояние от неё до конца
        var minDist = Double.greatestFiniteMagnitude
        var nearestIdx = 0
        for (i, coord) in polyline.enumerated() {
            let pt = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let d = location.distance(from: pt)
            if d < minDist { minDist = d; nearestIdx = i }
        }
        var total = 0.0
        for i in nearestIdx..<(polyline.count - 1) {
            let a = CLLocation(latitude: polyline[i].latitude, longitude: polyline[i].longitude)
            let b = CLLocation(latitude: polyline[i+1].latitude, longitude: polyline[i+1].longitude)
            total += a.distance(from: b)
        }
        return total / 1000.0  // км
    }

    // MARK: Persistence
    private func persist() {
        if let data = try? JSONEncoder().encode(routes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let loaded = try? JSONDecoder().decode([SavedRoute].self, from: data) else {
            if UserDefaults.standard.data(forKey: key) != nil {
                UserDefaults.standard.removeObject(forKey: key)
                Task { @MainActor in
                    DiagnosticsStore.shared.report(
                        title: "Сохранённые маршруты повреждены",
                        details: "Неверные данные маршрута удалены. Приложение продолжило запуск без старых маршрутов."
                    )
                }
            }
            return
        }
        routes = loaded
        activeRoute = loaded.first { $0.isActive }
    }
}
