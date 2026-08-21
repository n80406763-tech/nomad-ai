import Foundation
import CoreLocation

/// Поиск POI через Overpass API (бесплатный, данные OpenStreetMap)
/// Работает онлайн. Офлайн — из локальной SQLite БД (если скачана)
final class OverpassService {
    static let shared = OverpassService()
    private let baseURL = "https://overpass-api.de/api/interpreter"

    func searchPOI(category: POICategory, center: CLLocationCoordinate2D, radiusKm: Double, keyword: String? = nil) async -> [POIItem] {
        // Сначала пробуем офлайн
        let offline = searchOffline(category: category, center: center, radiusKm: radiusKm, keyword: keyword)
        if !offline.isEmpty { return offline }

        // Онлайн запрос к Overpass
        let query = buildQuery(category: category, lat: center.latitude, lon: center.longitude, radiusM: Int(radiusKm * 1000))
        guard let url = URL(string: baseURL) else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data("data=\(query)".utf8)
        req.timeoutInterval = 20

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return parseOverpassResponse(data: data, category: category, keyword: keyword)
    }

    private func buildQuery(category: POICategory, lat: Double, lon: Double, radiusM: Int) -> String {
        let tags: String
        switch category {
        case .fuel:        tags = "amenity=fuel"
        case .hotel:       tags = "tourism=hotel"
        case .supermarket: tags = "shop=supermarket"
        case .cafe:        tags = "amenity=cafe"
        case .pharmacy:    tags = "amenity=pharmacy"
        case .service:     tags = "shop=car_repair"
        case .atm:         tags = "amenity=atm"
        }
        return """
        [out:json][timeout:15];
        (
          node[\(tags)](around:\(radiusM),\(lat),\(lon));
          way[\(tags)](around:\(radiusM),\(lat),\(lon));
        );
        out center;
        """
    }

    private func parseOverpassResponse(data: Data, category: POICategory, keyword: String?) -> [POIItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

        var items: [POIItem] = []
        for el in elements {
            let tags = el["tags"] as? [String: String] ?? [:]
            let name = tags["name"] ?? tags["brand"] ?? ""
            let brand = tags["brand"]

            // Фильтр по ключевому слову
            if let kw = keyword, !kw.isEmpty {
                let haystack = (name + " " + (brand ?? "")).lowercased()
                guard haystack.contains(kw.lowercased()) else { continue }
            }

            // Координаты (node или way center)
            var lat: Double = 0, lon: Double = 0
            if let elLat = el["lat"] as? Double, let elLon = el["lon"] as? Double {
                lat = elLat; lon = elLon
            } else if let center = el["center"] as? [String: Double] {
                lat = center["lat"] ?? 0; lon = center["lon"] ?? 0
            }
            guard lat != 0, lon != 0 else { continue }

            let addr = [tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
            items.append(POIItem(
                id: UUID(),
                name: name,
                category: category,
                latitude: lat,
                longitude: lon,
                address: addr.isEmpty ? nil : addr,
                phone: tags["phone"],
                brand: brand
            ))
        }
        return items
    }

    // MARK: - Офлайн поиск (из локальной SQLite если скачана)
    private func searchOffline(category: POICategory, center: CLLocationCoordinate2D, radiusKm: Double, keyword: String?) -> [POIItem] {
        // TODO: подключить SQLite c заранее скачанными POI
        // Сейчас возвращаем пустой массив — будет реализовано в следующей версии
        return []
    }
}
