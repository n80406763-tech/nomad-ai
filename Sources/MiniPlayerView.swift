import SwiftUI

/// Мини-плеер — полоска внизу экрана при воспроизведении
struct MiniPlayerView: View {
    @ObservedObject var player = MusicPlayerService.shared

    var body: some View {
        if player.isPlaying || !player.currentTrack.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .foregroundColor(.cyan)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack.isEmpty ? "Нет трека" : player.currentTrack)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("Nomad AI Music")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()

                Button(action: player.previous) {
                    Image(systemName: "backward.fill").foregroundColor(.white)
                }
                Button(action: player.playPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(.cyan)
                        .font(.title3)
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill").foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
