import Foundation
import CoreLocation

/// Скачивает офлайн-данные (АЗС, отели, кафе, аптеки, шиномонтаж, банкоматы)
/// для всех регионов вдоль сохранённого маршрута через фоновую URLSession —
/// загрузка продолжается, даже если приложение свёрнуто.
final class RouteDownloadService: NSObject, ObservableObject {
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

    private let sessionIdentifier = "com.nomadai.app.routedownload"
    private var session: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?

    private var buffers: [Int: Data] = [:]
    private var taskToRegion: [Int: Int] = [:]
    private var startedAt: Date = Date()

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Вызывается из AppDelegate, когда система будит приложение для завершения фоновой загрузки
    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier else { completionHandler(); return }
        backgroundCompletionHandler = completionHandler
    }

    /// Начать скачивание точек интереса для всех регионов вдоль маршрута
    func startDownload(for route: SavedRoute) {
        guard state != .downloading else { return }
        let regions = Self.regionsAlong(polyline: route.polyline)

        DispatchQueue.main.async {
            self.totalRegions = regions.count
            self.completedRegions = 0
            self.progress = 0
            self.state = .downloading
            self.statusText = "Скачивание точек интереса: 0 из \(regions.count) регионов…"
            self.etaText = ""
        }
        buffers = [:]
        taskToRegion = [:]
        startedAt = Date()

        for (index, region) in regions.enumerated() {
            guard let task = makeUploadTask(center: region.center, radiusKm: region.radiusKm) else { continue }
            taskToRegion[task.taskIdentifier] = index
            buffers[task.taskIdentifier] = Data()
            task.resume()
        }

        if regions.isEmpty {
            DispatchQueue.main.async {
                self.state = .completed
                self.progress = 1
                self.statusText = "Маршрут короткий — офлайн-данные не требуются."
            }
        }
    }

    func cancelDownload() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        DispatchQueue.main.async {
            self.state = .idle
            self.progress = 0
        }
    }

    // MARK: - Построение запроса

    private func makeUploadTask(center: CLLocationCoordinate2D, radiusKm: Double) -> URLSessionUploadTask? {
        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return nil }
        let query = Self.buildQuery(center: center, radiusKm: radiusKm)
        let bodyString = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        guard let bodyData = bodyString.data(using: .utf8) else { return nil }

        // Фоновые сессии требуют, чтобы тело запроса было файлом, а не данными в памяти
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".body")
        do {
            try bodyData.write(to: tmpURL, options: .atomic)
        } catch {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return session.uploadTask(with: request, fromFile: tmpURL)
    }

    private static func buildQuery(center: CLLocationCoordinate2D, radiusKm: Double) -> String {
        let radiusM = Int(radiusKm * 1000)
        let tags = ["amenity=fuel", "tourism=hotel", "shop=supermarket", "amenity=cafe", "amenity=pharmacy", "shop=car_repair", "amenity=atm"]
        let body = tags.map {
            "node[\($0)](around:\(radiusM),\(center.latitude),\(center.longitude)); way[\($0)](around:\(radiusM),\(center.latitude),\(center.longitude));"
        }.joined(separator: "\n  ")
        return """
        [out:json][timeout:25];
        (
          \(body)
        );
        out center;
        """
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

    // MARK: - Прогресс

    private func updateProgress() {
        DispatchQueue.main.async {
            guard self.totalRegions > 0 else { return }
            self.progress = Double(self.completedRegions) / Double(self.totalRegions)
            self.statusText = "Скачивание точек интереса: \(self.completedRegions) из \(self.totalRegions) регионов…"

            let elapsed = Date().timeIntervalSince(self.startedAt)
            if self.completedRegions > 0 {
                let perRegion = elapsed / Double(self.completedRegions)
                let remaining = perRegion * Double(self.totalRegions - self.completedRegions)
                if remaining > 60 {
                    self.etaText = "Осталось примерно \(Int(remaining / 60)) мин"
                } else if remaining > 1 {
                    self.etaText = "Осталось примерно \(Int(remaining)) сек"
                } else {
                    self.etaText = ""
                }
            }

            if self.completedRegions >= self.totalRegions {
                self.state = .completed
                self.statusText = "Все офлайн-данные вдоль маршрута загружены."
                self.etaText = ""
            }
        }
    }
}

// MARK: - URLSessionDataDelegate / URLSessionTaskDelegate
extension RouteDownloadService: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            buffers[task.taskIdentifier] = nil
            taskToRegion[task.taskIdentifier] = nil
        }
        guard error == nil, let data = buffers[task.taskIdentifier] else {
            DispatchQueue.main.async { self.completedRegions += 1 }
            self.updateProgress()
            return
        }
        let items = Self.parsePOIs(data: data)
        if !items.isEmpty {
            POIOfflineCache.shared.append(items)
        }
        DispatchQueue.main.async { self.completedRegions += 1 }
        updateProgress()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    private static func parsePOIs(data: Data) -> [POIItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

        var items: [POIItem] = []
        for el in elements {
            let tags = el["tags"] as? [String: String] ?? [:]
            guard let category = OverpassService.category(fromTags: tags) else { continue }
            var lat: Double = 0, lon: Double = 0
            if let elLat = el["lat"] as? Double, let elLon = el["lon"] as? Double {
                lat = elLat; lon = elLon
            } else if let center = el["center"] as? [String: Double] {
                lat = center["lat"] ?? 0; lon = center["lon"] ?? 0
            }
            guard lat != 0, lon != 0 else { continue }
            let name = tags["name"] ?? tags["brand"] ?? category.rawValue
            let addr = [tags["addr:street"], tags["addr:housenumber"]].compactMap { $0 }.joined(separator: " ")
            items.append(POIItem(
                id: UUID(),
                name: name,
                category: category,
                latitude: lat,
                longitude: lon,
                address: addr.isEmpty ? nil : addr,
                phone: tags["phone"],
                brand: tags["brand"]
            ))
        }
        return items
    }
}
