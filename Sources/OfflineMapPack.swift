import Foundation

enum OfflineMapPack {
    static let resourceDirectory = "VectorMap"

    static var russiaURL: URL? {
        Bundle.main.url(forResource: "russia", withExtension: "pmtiles", subdirectory: resourceDirectory)
            ?? Bundle.main.url(forResource: "russia", withExtension: "pmtiles")
    }

    static var isBundled: Bool {
        russiaURL != nil
    }

    static var bundledSizeText: String {
        guard let russiaURL,
              let values = try? russiaURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return "не найден" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}