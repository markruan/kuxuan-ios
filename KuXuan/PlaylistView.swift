import SwiftUI

struct PlaylistView: View {
    @EnvironmentObject var player: PlayerEngine
    let ref: PlaylistRef
    @State private var detail: PlaylistDetailResp?
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        Group {
            if let d = detail {
                if d.code == -1 {
                    errorView(d.reason.isEmpty ? "加载失败" : d.reason)
                } else {
                    content(d)
                }
            } else if loading {
                ProgressView("加载中…")
            } else {
                errorView(errorMsg ?? "加载失败")
            }
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: PlaylistDetailResp) -> some View {
        let songs = d.songs
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 头部
                HStack(spacing: 14) {
                    KXCover(url: APIClient.coverURL(d.info?.cover ?? ref.cover))
                        .frame(width: 110, height: 110).cornerRadius(12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.info?.name ?? ref.name).font(.title3.bold()).lineLimit(2)
                        if let p = d.info {
                            Text("\(p.trackCount) 首 · 播放 \(p.playCountText)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Button {
                            if !songs.isEmpty { player.playSongs(songs, index: 0) }
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Color.pink).cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // 歌曲列表
                LazyVStack(spacing: 4) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                        songRow(s, i)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 90)
            }
            .padding(.top, 12)
        }
    }

    private func songRow(_ s: Song, _ i: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(i + 1)").font(.subheadline).foregroundColor(.secondary)
                .frame(width: 26, alignment: .center)
            KXCover(url: APIClient.coverURL(s.cover))
                .frame(width: 44, height: 44).cornerRadius(8)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.subheadline).lineLimit(1)
                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button {
                player.toggleFav(s)
            } label: {
                Image(systemName: player.isFav(s.id) ? "heart.fill" : "heart")
                    .foregroundColor(player.isFav(s.id) ? .pink : .secondary)
            }
            .padding(.trailing, 8)
        }
        .padding(8).background(
            player.current?.id == s.id ? Color.pink.opacity(0.12) : Color.clear
        ).cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture { player.playSongs(detail?.songs ?? [], index: i) }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(msg).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loading = true; errorMsg = nil; detail = nil
        do { detail = try await APIClient.playlist(id: ref.id) }
        catch { errorMsg = "无法加载歌单" }
        loading = false
    }
}
