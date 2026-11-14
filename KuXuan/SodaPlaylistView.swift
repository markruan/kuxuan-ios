import SwiftUI

/// 汽水歌单详情页（个人测试）。
///
/// 与 `PlaylistView` 视觉一致（居中大封面 → 标题 → 播放/随机 → 歌曲列表），
/// 但完全解耦网易云：数据来自 `API.sodaPlaylistTracks`，播放走 `player.playSongs`
/// （汽水加密流由 PlayerEngine 自动经本地 bridge 解密后播放）。不含网易云「收藏歌单」逻辑。
struct SodaPlaylistView: View {
    @EnvironmentObject var player: PlayerEngine
    let id: String
    let name: String
    let cover: String

    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        Group {
            if !loading, songs.isEmpty {
                errorView(errorMsg ?? "这个歌单暂时没有曲目")
            } else if loading {
                KXPlaylistSkeleton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                content
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .animation(.easeInOut(duration: 0.32), value: loading)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                Divider().padding(.horizontal, 20)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                        songRow(s, i)
                        Divider().padding(.leading, 76)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .padding(.top, 8)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 14) {
            KXCover(url: APIClient.coverURL(cover, size: 420))
                .frame(width: 210, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            VStack(spacing: 5) {
                Text(name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(songs.count) 首").font(.caption).foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                    Text("汽水音乐")
                        .font(.caption2).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color(red: 0.06, green: 0.43, blue: 0.34))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                actionButton(icon: .play, title: "播放", primary: true) {
                    if !songs.isEmpty { player.playSongs(songs, index: 0) }
                }
                actionButton(icon: .shuffle, title: "随机播放", primary: false) {
                    guard !songs.isEmpty else { return }
                    player.playMode = 2
                    player.playSongs(songs, index: Int.random(in: 0..<songs.count))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private func actionButton(icon: KXIconName, title: String, primary: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                KXIcon(icon: icon, size: 15,
                       color: primary ? .white : .kxAccent, filled: primary)
                Text(title).font(KXFont.scaled(14, weight: .semibold))
            }
            .foregroundColor(primary ? .white : .kxAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 10)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient.kx)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func songRow(_ s: Song, _ i: Int) -> some View {
        let playing = player.current?.id == s.id
        return HStack(spacing: 12) {
            if playing {
                KXIcon(icon: .wave, size: 15, color: .kxAccent)
                    .frame(width: 22, alignment: .center)
            } else {
                Text("\(i + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 22, alignment: .center)
            }

            KXCover(url: APIClient.coverURL(s.cover, size: 120))
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(KXFont.scaled(15, weight: .medium)).lineLimit(1)
                    .foregroundColor(playing ? .kxAccent : .primary)
                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(i + 1) 首，\(s.title)，\(s.artist)")
        .accessibilityAction(named: "播放") {
            player.playSongs(songs, index: i)
        }
        .onTapGesture { player.playSongs(songs, index: i) }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            KXIcon(icon: .warning, size: 40, color: .orange)
            Text(msg).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderedProminent).tint(.kxAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loading = true; errorMsg = nil; songs = []
        do {
            songs = try await APIClient.sodaPlaylistTracks(id: id)
        } catch {
            errorMsg = "无法加载歌单"
        }
        loading = false
    }
}
