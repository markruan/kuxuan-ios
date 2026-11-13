import SwiftUI

/// 歌手页（中等丰富度）入口：由 RootView 的 fullScreenCover(item: $player.artistToShow) 承接。
/// 内部用 NavigationStack(path:) 支持「点相似歌手 → 层层下钻」到另一个歌手页。
struct ArtistView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let mini: MiniArtist

    @State private var path: [MiniArtist] = []

    var body: some View {
        NavigationStack(path: $path) {
            ArtistDetailContent(mini: mini, path: $path)
                .navigationDestination(for: MiniArtist.self) { a in
                    ArtistDetailContent(mini: a, path: $path)
                }
        }
        // 收藏歌手的提示浮层：歌手页是全屏浮层，会盖住播放页的 toast，这里单独挂一份
        .overlay(alignment: .top) {
            FavSyncToast().padding(.top, 52)
        }
    }
}

/// 歌手页正文：头部大封面 + 名 + 单曲/专辑数 + ♡收藏 + 播放全部；
/// 热门歌曲列表；相似歌手横向；专辑横向；可展开简介。
struct ArtistDetailContent: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let mini: MiniArtist
    @Binding var path: [MiniArtist]

    @State private var detail: KBArtistDetail?
    @State private var songs: [Song] = []
    @State private var albums: [ArtistAlbum] = []
    @State private var similar: [MiniArtist] = []
    @State private var loading = true
    @State private var err: String?
    @State private var bioExpanded = false

    private var faved: Bool { player.favArtists.contains { $0.id == mini.id } }
    private var currentArtist: MiniArtist {
        MiniArtist(id: detail?.id ?? mini.id,
                   name: detail?.name ?? mini.name,
                   cover: detail?.cover ?? mini.cover)
    }
    private var bioText: String { detail?.bioText ?? "" }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            LinearGradient(colors: [Color.kxBrand2.opacity(0.22),
                                    Color.kxBrand3.opacity(0.08), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Group {
                    if loading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("加载中…").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let e = err {
                        VStack(spacing: 12) {
                            KXIcon(icon: .warning, size: 40, color: .orange)
                            Text(e).font(.subheadline).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 30)
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderedProminent).tint(.kxAccent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) { bodyContent }
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: 顶部栏：收起整页 + （下钻后）返回上一层
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { player.artistToShow = nil } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .primary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Spacer()
            if !path.isEmpty {
                Button { path.removeLast() } label: {
                    KXIcon(icon: .chevronLeft, size: 20, color: .primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            actions
            if !songs.isEmpty { hotSongsSection }
            if !similar.isEmpty { similarSection }
            if !albums.isEmpty { albumsSection }
            if !bioText.isEmpty { bioSection }
            Spacer(minLength: 50)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: 头部：大封面 + 名 + 单曲/专辑数
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            KXCover(url: APIClient.coverURL(detail?.cover ?? mini.cover, size: 300))
                .frame(width: 112, height: 112)
                .cornerRadius(12)
                .shadow(radius: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(detail?.name ?? mini.name)
                    .font(.title2.bold()).lineLimit(2)
                if let d = detail {
                    Text("单曲 \(d.musicSize) · 专辑 \(d.albumSize)")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("歌手").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: 收藏 + 播放全部
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                player.toggleFavArtist(currentArtist)
            } label: {
                HStack(spacing: 6) {
                    KXIcon(icon: faved ? .heartFill : .heart,
                           size: 16, color: faved ? .kxAccent : .primary)
                    Text(faved ? "已收藏" : "收藏").font(.subheadline)
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)

            Button {
                guard !songs.isEmpty else { return }
                player.playSongs(songs, index: 0)
                player.artistToShow = nil   // 收起歌手页，露出全屏播放器
            } label: {
                HStack(spacing: 6) {
                    KXIcon(icon: .play, size: 16, color: .white)
                    Text("播放全部").font(.subheadline.bold())
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(Color.kxAccent))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 热门歌曲
    private var hotSongsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("热门歌曲")
            LazyVStack(spacing: 4) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    Button {
                        player.playSongs(songs, index: i)
                        player.artistToShow = nil
                    } label: {
                        HStack(spacing: 12) {
                            KXCover(url: APIClient.coverURL(s.cover, size: 120))
                                .frame(width: 46, height: 46).cornerRadius(6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if player.current?.id == s.id {
                                KXIcon(icon: .wave, size: 17, color: .kxAccent)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 相似歌手（横向）
    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("相似歌手")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(similar) { a in
                        Button { path.append(a) } label: {
                            VStack(spacing: 6) {
                                KXCover(url: APIClient.coverURL(a.cover, size: 140))
                                    .frame(width: 74, height: 74)
                                    .clipShape(Circle())
                                Text(a.name).font(.caption).lineLimit(1)
                                    .frame(width: 74)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: 专辑（横向）
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("专辑")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(albums) { al in
                        VStack(alignment: .leading, spacing: 5) {
                            KXCover(url: APIClient.coverURL(al.cover, size: 160))
                                .frame(width: 96, height: 96).cornerRadius(8)
                            Text(al.name).font(.caption2).lineLimit(2)
                                .frame(width: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: 简介（可展开）
    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("歌手简介")
            VStack(alignment: .leading, spacing: 6) {
                Text(bioText)
                    .font(.subheadline).foregroundColor(.secondary)
                    .lineLimit(bioExpanded ? nil : 4)
                    .animation(.easeInOut(duration: 0.25), value: bioExpanded)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { bioExpanded.toggle() }
                } label: {
                    Text(bioExpanded ? "收起" : "展开全文")
                        .font(.caption).foregroundColor(.kxAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func load() async {
        loading = true; err = nil
        do {
            let resp = try await APIClient.artistDetail(id: mini.id)
            detail = resp.artist
            songs = resp.songs
            albums = resp.albums
            similar = resp.similar
        } catch {
            err = "歌手信息加载失败：\(error.localizedDescription)"
        }
        loading = false
    }
}
