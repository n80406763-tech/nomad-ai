import Foundation

/// Локальный офлайн-кэш точек интереса (АЗС, отели, кафе и т.д.),
/// скачанных заранее для регионов вдоль маршрута.
final class POIOfflineCache {
    static let shared = POIOfflineCache()

    private let fileURL: URL
    private(set) var items: [POIItem] = []
    private let queue = DispatchQueue(label: "com.nomadai.app.poicache", attributes: .concurrent)

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("poi_offline_cache.json")
        load()
    }

    func append(_ newItems: [POIItem]) {
        queue.async(flags: .barrier) {
            var merged = self.items
            for item in newItems {
                let exists = merged.contains {
                    $0.category == item.category &&
                    abs($0.latitude - item.latitude) < 0.0003 &&
                    abs($0.longitude - item.longitude) < 0.0003
                }
                if !exists { merged.append(item) }
            }
            self.items = merged
            self.persist()
        }
    }

    func search(category: POICategory, center: CLLocationCoordinate2D, radiusKm: Double, keyword: String?) -> [POIItem] {
        queue.sync {
            items.filter { item in
                guard item.category == category else { return false }
                let d = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    .distance(from: CLLocation(latitude: item.latitude, longitude: item.longitude))
                guard d <= radiusKm * 1000 else { return false }
                if let kw = keyword, !kw.isEmpty {
                    let haystack = (item.name + " " + (item.brand ?? "")).lowercased()
                    return haystack.contains(kw.lowercased())
                }
                return true
            }
        }
    }

    var regionCount: Int { items.count }

    func clear() {
        queue.async(flags: .barrier) {
            self.items = []
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([POIItem].self, from: data) else { return }
        items = loaded
    }
}

import CoreLocation
