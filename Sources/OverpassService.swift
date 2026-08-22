import Foundation
import CoreLocation

/// Поиск POI через Overpass API (бесплатный, данные OpenStreetMap)
/// Работает онлайн. Офлайн — из локальной SQLite БД (если скачана)
final class OverpassService {
    static let shared = OverpassService()

    func searchPOI(category: POICategory, center: CLLocationCoordinate2D, radiusKm: Double, keyword: String? = nil) async -> [POIItem] {
        POIOfflineCache.shared.search(category: category, center: center, radiusKm: radiusKm, keyword: keyword)
    }

    /// Тег категории -> POICategory, используется при разборе больших офлайн-выгрузок по маршруту
    static func category(fromTags tags: [String: String]) -> POICategory? {
        if tags["amenity"] == "fuel" { return .fuel }
        if tags["tourism"] == "hotel" { return .hotel }
        if tags["shop"] == "supermarket" { return .supermarket }
        if tags["amenity"] == "cafe" { return .cafe }
        if tags["amenity"] == "pharmacy" { return .pharmacy }
        if tags["shop"] == "car_repair" { return .service }
        if tags["amenity"] == "atm" { return .atm }
        return nil
    }
}
