import Foundation
import CoreLocation

struct OfflinePlaceResult: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let kind: String
    let population: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name = "n"
        case aliases = "a"
        case latitude = "lat"
        case longitude = "lon"
        case kind = "k"
        case population = "p"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        kind.isEmpty ? name : "\(name) — \(kind)"
    }
}

private struct OfflinePlaceIndex: Decodable {
    let places: [OfflinePlaceResult]

    enum CodingKeys: String, CodingKey {
        case places = "p"
    }
}

private struct IndexedOfflinePlace: Sendable {
    let place: OfflinePlaceResult
    let names: [String]
}

actor OfflinePlaceSearchService {
    static let shared = OfflinePlaceSearchService()

    private var index: [IndexedOfflinePlace]?
    private var didReportUnavailable = false

    func search(query: String, limit: Int = 8) -> [OfflinePlaceResult] {
        let normalizedQuery = Self.normalize(query)
        guard normalizedQuery.count >= 2 else { return [] }

        let matches = loadIndex().compactMap { item -> (OfflinePlaceResult, Int)? in
            let score = score(for: item.names, query: normalizedQuery, population: item.place.population)
            return score > 0 ? (item.place, score) : nil
        }

        return matches
            .sorted {
                if $0.1 == $1.1 { return $0.0.population > $1.0.population }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    private func loadIndex() -> [IndexedOfflinePlace] {
        if let index { return index }

        let places: [OfflinePlaceResult]
        if let url = Bundle.main.url(forResource: "russia_places", withExtension: "json", subdirectory: "OfflineSearch")
            ?? Bundle.main.url(forResource: "russia_places", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(OfflinePlaceIndex.self, from: data) {
            places = decoded.places
        } else {
            places = Self.fallbackPlaces
            reportUnavailable()
        }

        let builtIndex = places.map { place in
            IndexedOfflinePlace(
                place: place,
                names: Array(Set(([place.name] + place.aliases).map(Self.normalize))).filter { !$0.isEmpty }
            )
        }
        index = builtIndex
        return builtIndex
    }

    private func score(for names: [String], query: String, population: Int) -> Int {
        var bestScore = 0
        for name in names {
            if name == query {
                bestScore = max(bestScore, 10_000)
            } else if name.hasPrefix(query) {
                bestScore = max(bestScore, 7_000)
            } else if name.contains(query) {
                bestScore = max(bestScore, 3_000)
            }
        }

        let tokens = query.split(separator: " ").map(String.init)
        if tokens.count > 1,
           names.contains(where: { candidate in tokens.allSatisfy(candidate.contains) }) {
            bestScore = max(bestScore, 5_000)
        }

        guard bestScore > 0 else { return 0 }
        return bestScore + min(800, Int(log10(Double(max(population, 1))) * 100))
    }

    private func reportUnavailable() {
        guard !didReportUnavailable else { return }
        didReportUnavailable = true
        Task { @MainActor in
            DiagnosticsStore.shared.report(
                title: "Офлайн-поиск неполный",
                details: "Индекс населённых пунктов России не найден в пакете. Доступны основные города."
            )
        }
    }

    private static func normalize(_ value: String) -> String {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        let allowed = CharacterSet.letters.union(.decimalDigits)
        return normalized
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let fallbackPlaces = [
        OfflinePlaceResult(id: "moscow", name: "Москва", aliases: ["Moscow"], latitude: 55.7558, longitude: 37.6173, kind: "город", population: 13_000_000),
        OfflinePlaceResult(id: "saint-petersburg", name: "Санкт-Петербург", aliases: ["Петербург", "Saint Petersburg"], latitude: 59.9343, longitude: 30.3351, kind: "город", population: 5_600_000),
        OfflinePlaceResult(id: "novorossiysk", name: "Новороссийск", aliases: ["Novorossiysk"], latitude: 44.7236, longitude: 37.7680, kind: "город", population: 340_000),
        OfflinePlaceResult(id: "yekaterinburg", name: "Екатеринбург", aliases: ["Ekaterinburg"], latitude: 56.8389, longitude: 60.6057, kind: "город", population: 1_500_000),
        OfflinePlaceResult(id: "novosibirsk", name: "Новосибирск", aliases: ["Novosibirsk"], latitude: 55.0084, longitude: 82.9357, kind: "город", population: 1_600_000),
        OfflinePlaceResult(id: "kazan", name: "Казань", aliases: ["Kazan"], latitude: 55.7961, longitude: 49.1064, kind: "город", population: 1_300_000),
        OfflinePlaceResult(id: "sochi", name: "Сочи", aliases: ["Sochi"], latitude: 43.5855, longitude: 39.7231, kind: "город", population: 430_000),
        OfflinePlaceResult(id: "rostov", name: "Ростов-на-Дону", aliases: ["Ростов", "Rostov-on-Don"], latitude: 47.2357, longitude: 39.7015, kind: "город", population: 1_100_000)
    ]
}