import Foundation
import UIKit

struct OSMTileKey: Hashable {
    let zoom: Int
    let x: Int
    let y: Int

    var identifier: String { "\(zoom)/\(x)/\(y)" }
}

final class OSMTileStore {
    static let shared = OSMTileStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.nomadai.app.osmtiles")
    private var pendingLoads: [OSMTileKey: [(UIImage?) -> Void]] = [:]
    private let cacheDirectory: URL

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = root.appendingPathComponent("OSMTiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 256
    }

    func image(for key: OSMTileKey, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = key.identifier as NSString
        if let image = memoryCache.object(forKey: cacheKey) {
            DispatchQueue.main.async { completion(image) }
            return
        }

        ioQueue.async {
            if let image = self.loadStoredImage(for: key) {
                self.memoryCache.setObject(image, forKey: cacheKey)
                DispatchQueue.main.async { completion(image) }
                return
            }

            if self.pendingLoads[key] != nil {
                self.pendingLoads[key, default: []].append(completion)
                return
            }

            self.pendingLoads[key] = [completion]
            self.loadFromOpenStreetMap(key)
        }
    }

    private func loadStoredImage(for key: OSMTileKey) -> UIImage? {
        if let bundledURL = Bundle.main.url(
            forResource: "\(key.y)",
            withExtension: "png",
            subdirectory: "OfflineTiles/\(key.zoom)/\(key.x)"
        ), let image = UIImage(contentsOfFile: bundledURL.path) {
            return image
        }

        return UIImage(contentsOfFile: diskURL(for: key).path)
    }

    private func loadFromOpenStreetMap(_ key: OSMTileKey) {
        guard let url = URL(string: "https://tile.openstreetmap.org/\(key.zoom)/\(key.x)/\(key.y).png") else {
            finish(key, image: nil, data: nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("Nomad/1.1 (+https://github.com/n80406763-tech/nomad-ai)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let image: UIImage?
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data {
                image = UIImage(data: data)
            } else {
                image = nil
            }
            self?.ioQueue.async {
                self?.finish(key, image: image, data: image == nil ? nil : data)
            }
        }.resume()
    }

    private func finish(_ key: OSMTileKey, image: UIImage?, data: Data?) {
        if let image {
            memoryCache.setObject(image, forKey: key.identifier as NSString)
            if let data {
                let fileURL = diskURL(for: key)
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: fileURL, options: .atomic)
            }
        }

        let completions = pendingLoads.removeValue(forKey: key) ?? []
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private func diskURL(for key: OSMTileKey) -> URL {
        cacheDirectory
            .appendingPathComponent("\(key.zoom)", isDirectory: true)
            .appendingPathComponent("\(key.x)", isDirectory: true)
            .appendingPathComponent("\(key.y).png")
    }
}