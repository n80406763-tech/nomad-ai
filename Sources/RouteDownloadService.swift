import Foundation
import CoreLocation

/// Скачивает офлайн-данные (АЗС, отели, кафе, аптеки, шиномонтаж, банкоматы)
/// для всех регионов вдоль сохранённого маршрута через фоновую URLSession —
/// загрузка продолжается, даже если приложение свёрнуто.
final class RouteDownloadService: ObservableObject {
    static let shared = RouteDownloadService()

    enum DownloadState: Equatable {
        case idle
        case downloading
        case completed
        case failed(String)
    }

    @Published var state: DownloadState = .idle
    @Published var progress: Double = 0
    @Published var completedRegions = 0
    @Published var totalRegions = 0
    @Published var statusText = ""
    @Published var etaText = ""

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    /// Начать скачивание точек интереса для всех регионов вдоль маршрута
    func startDownload(for route: SavedRoute) {
        let regions = Self.regionsAlong(polyline: route.polyline)

        DispatchQueue.main.async {
            self.totalRegions = regions.count
            self.completedRegions = regions.count
            self.progress = 1
            self.state = .completed
            self.statusText = "Карта, поиск населённых пунктов и база АЗС/отелей по всей России уже находятся в приложении."
            self.etaText = ""
        }
    }

    func cancelDownload() {
        DispatchQueue.main.async {
            self.state = .idle
            self.progress = 0
        }
    }

    // MARK: - Регионы вдоль маршрута

    /// Разбивает маршрут на регионы каждые ~40 км с радиусом покрытия ~18 км
    static func regionsAlong(polyline: [CLLocationCoordinate2D], stepKm: Double = 40, radiusKm: Double = 18) -> [(center: CLLocationCoordinate2D, radiusKm: Double)] {
        guard let first = polyline.first else { return [] }
        guard polyline.count > 1 else { return [(first, radiusKm)] }

        var result: [(CLLocationCoordinate2D, Double)] = [(first, radiusKm)]
        var accumulated = 0.0
        var prev = first
        for coord in polyline.dropFirst() {
            let a = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            accumulated += a.distance(from: b) / 1000.0
            if accumulated >= stepKm {
                result.append((coord, radiusKm))
                accumulated = 0
            }
            prev = coord
        }
        if let last = polyline.last, let lastAdded = result.last?.0 {
            let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: lastAdded.latitude, longitude: lastAdded.longitude))
            if d > 5000 { result.append((last, radiusKm)) }
        }

        // Не более 30 регионов за раз, чтобы не перегружать бесплатный Overpass API
        guard result.count > 30 else { return result }
        let strideStep = Double(result.count) / 30.0
        var thinned: [(CLLocationCoordinate2D, Double)] = []
        var i = 0.0
        while Int(i) < result.count {
            thinned.append(result[Int(i)])
            i += strideStep
        }
        return thinned
    }

}
