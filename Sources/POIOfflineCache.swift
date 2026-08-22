import Foundation

private struct BundledPOI: Decodable {
    let id: Int64
    let k: String
    let n: String?
    let lat: Double
    let lon: Double
    let d: String?
    let ph: String?
    let b: String?
}

private struct BundledPOIIndex: Decodable {
    let points: [BundledPOI]
    enum CodingKeys: String, CodingKey { case points = "p" }
}

/// Локальный офлайн-кэш точек интереса (АЗС, отели, кафе и т.д.).
/// Основной набор данных по всей России зашит в бандл приложения
/// (Resources/OfflinePOI/russia_pois.json, собран на CI из OpenStreetMap).
final class POIOfflineCache {
    static let shared = POIOfflineCache()

    private let fileURL: URL
    private(set) var items: [POIItem] = []
    private let queue = DispatchQueue(label: "com.nomadai.app.poicache", attributes: .concurrent)
    private var didReportBundleUnavailable = false

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("poi_offline_cache.json")
        loadBundled()
        load()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "russia_pois", withExtension: "json", subdirectory: "OfflinePOI")
            ?? Bundle.main.url(forResource: "russia_pois", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(BundledPOIIndex.self, from: data) else {
            reportBundleUnavailable()
            return
        }

        items = decoded.points.compactMap { point in
            guard let category = POICategory(bundledCode: point.k) else { return nil }
            return POIItem(
                id: UUID(),
                name: point.n ?? category.rawValue,
                category: category,
                latitude: point.lat,
                longitude: point.lon,
                address: point.d,
                phone: point.ph,
                brand: point.b
            )
        }
    }

    private func reportBundleUnavailable() {
        guard !didReportBundleUnavailable else { return }
        didReportBundleUnavailable = true
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "Офлайн-база АЗС/отелей не найдена",
                details: "Пакет точек интереса России не попал в сборку приложения. Поиск заправок и отелей будет пустым."
            )
        }
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

    /// Подмешивает точки, сохранённые локально ещё старой (сетевой) версией
    /// приложения, поверх бандла — не заменяет его, чтобы не потерять
    /// основной набор данных по всей России.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([POIItem].self, from: data),
              !loaded.isEmpty else { return }
        var merged = items
        for item in loaded {
            let exists = merged.contains {
                $0.category == item.category &&
                abs($0.latitude - item.latitude) < 0.0003 &&
                abs($0.longitude - item.longitude) < 0.0003
            }
            if !exists { merged.append(item) }
        }
        items = merged
    }
}

import CoreLocation
