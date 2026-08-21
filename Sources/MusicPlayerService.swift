import Foundation
import AVFoundation

/// Плеер для локальных mp3 файлов из Documents/Music (папка доступна через "Файлы")
final class MusicPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayerService()

    @Published var isPlaying = false
    @Published var currentTrack: String = ""
    @Published var tracks: [URL] = []

    private var player: AVAudioPlayer?

    override init() {
        super.init()
        setupAudioSession()
        refreshTracks()
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func refreshTracks() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicDir = docs.appendingPathComponent("Music")
        // Создаём папку если не существует
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)

        let exts = ["mp3", "m4a", "aac", "wav", "flac"]
        guard let files = try? FileManager.default.contentsOfDirectory(at: musicDir, includingPropertiesForKeys: nil) else { return }
        tracks = files.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Найти и воспроизвести трек по запросу (нечёткий поиск)
    @discardableResult
    func play(query: String) -> Bool {
        refreshTracks()
        let q = query.lowercased()
        // Нечёткий поиск: ищем совпадение в названии файла
        let match = tracks.first {
            let name = $0.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains(q) || q.split(separator: " ").allSatisfy { name.contains($0) }
        }
        guard let url = match else { return false }
        playURL(url)
        return true
    }

    func playURL(_ url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        currentTrack = url.deletingPathExtension().lastPathComponent
        isPlaying = true
    }

    func playPause() {
        guard let p = player else { return }
        if p.isPlaying { p.pause(); isPlaying = false }
        else { p.play(); isPlaying = true }
    }

    func next() {
        guard let current = tracks.first(where: { $0.lastPathComponent == currentTrack + ".mp3" }) ?? tracks.first,
              let idx = tracks.firstIndex(of: current) else { return }
        let next = tracks[(idx + 1) % tracks.count]
        playURL(next)
    }

    func previous() {
        guard let current = tracks.first(where: { $0.lastPathComponent == currentTrack + ".mp3" }) ?? tracks.first,
              let idx = tracks.firstIndex(of: current) else { return }
        let prev = tracks[(idx - 1 + tracks.count) % tracks.count]
        playURL(prev)
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.next()  // Автопроигрывание следующего трека
        }
    }
}
