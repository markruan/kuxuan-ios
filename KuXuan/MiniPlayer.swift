import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    var body: some View {
        HStack(spacing: 12) {
            Button { player.showFullPlayer = true } label: {
                KXCover(url: APIClient.coverURL(player.current?.cover))
                    .frame(width: 44, height: 44).cornerRadius(8)
            }
            Button {
                player.showFullPlayer = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "未在播放")
                        .font(.subheadline).lineLimit(1)
                    Text(player.current?.artist ?? "—")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).foregroundColor(.primary)
            }
            .frame(width: 36, height: 36)
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title3).foregroundColor(.primary)
            }
            .frame(width: 36, height: 36)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
