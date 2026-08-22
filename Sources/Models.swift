import Foundation
import CoreLocation

/// Модель сохранённого маршрута
struct SavedRoute: Identifiable, Codable {
    let id: UUID
    var name: String
    var waypoints: [Waypoint]        // промежуточные точки (название + коорд)
    var polyline: [CLLocationCoordinate2D]  // запомненная линия маршрута
    var totalDistanceKm: Double
    var createdAt: Date
    var isActive: Bool

    // Кастомный Codable для CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, name, waypoints, polylineCoords, totalDistanceKm, createdAt, isActive
    }
    init(id: UUID = UUID(), name: String, waypoints: [Waypoint], polyline: [CLLocationCoordinate2D], totalDistanceKm: Double) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.polyline = polyline
        self.totalDistanceKm = totalDistanceKm
        self.createdAt = Date()
        self.isActive = false
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        waypoints = try c.decode([Waypoint].self, forKey: .waypoints)
        totalDistanceKm = try c.decode(Double.self, forKey: .totalDistanceKm)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        let coords = try c.decode([[Double]].self, forKey: .polylineCoords)
        polyline = try coords.map { pair in
            guard pair.count == 2,
                  pair[0].isFinite,
                  pair[1].isFinite,
                  (-90...90).contains(pair[0]),
                  (-180...180).contains(pair[1]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath,
                    debugDescription: "Некорректная координата маршрута"
                ))
            }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(waypoints, forKey: .waypoints)
        try c.encode(totalDistanceKm, forKey: .totalDistanceKm)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isActive, forKey: .isActive)
        let coords = polyline.map { [$0.latitude, $0.longitude] }
        try c.encode(coords, forKey: .polylineCoords)
    }
}

struct Waypoint: Identifiable, Codable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
    }
}

/// POI — заправка, отель, магазин и т.д.
struct POIItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: POICategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var phone: String?
    var brand: String?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum POICategory: String, Codable, CaseIterable {
    case fuel       = "Заправки"
    case hotel      = "Отели"
    case supermarket = "Супермаркеты"
    case cafe       = "Кафе"
    case pharmacy   = "Аптеки"
    case service    = "Шиномонтаж/СТО"
    case atm        = "Банкоматы"

    /// Короткий код категории в бандле офлайн-POI (см. Tools/build-offline-poi-index.mjs).
    init?(bundledCode: String) {
        switch bundledCode {
        case "f": self = .fuel
        case "h": self = .hotel
        case "s": self = .supermarket
        case "c": self = .cafe
        case "p": self = .pharmacy
        case "r": self = .service
        case "a": self = .atm
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .hotel: return "bed.double.fill"
        case .supermarket: return "cart.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .pharmacy: return "cross.fill"
        case .service: return "wrench.and.screwdriver.fill"
        case .atm: return "banknote.fill"
        }
    }

    var color: String {
        switch self {
        case .fuel: return "orange"
        case .hotel: return "blue"
        case .supermarket: return "green"
        case .cafe: return "brown"
        case .pharmacy: return "red"
        case .service: return "gray"
        case .atm: return "yellow"
        }
    }
}
