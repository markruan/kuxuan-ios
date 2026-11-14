import SwiftUI

/// 汽水探索模式全页（个人测试）。
///
/// 第一屏：feed_mode 的全部听歌模式（约 45 个）铺成网格；
/// 点任意模式 → 取该模式的 discover_mix 歌单列表；点歌单 → 进 SodaPlaylistView。
/// 两层切换用内部 state，不依赖外部 navigationDestination 注册，跳转稳。
struct SodaModesView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore

    /// 首页探索模式卡片点入时，直接定位到该模式（传 scene_mode_id）。
    var initialSceneId: String?

    @State private var scenes: [[String: Any]] = []
    @State private var loading = true
    @State private var errorMsg: String?

    @State private var selected: [String: Any]? = nil
    @State private var playlists: [SodaPlaylist] = []
    @State private var loadingPlaylists = false
    @State private var playlistError: String?

    var body: some View {
        Group {
            if let sel = selected {
                playlistList(for: sel)
            } else if !auth.sodaBound {
                notBoundView
            } else if loading {
                ProgressView("加载听歌模式…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scenes.isEmpty {
                errorView(errorMsg ?? "暂无可用的听歌模式")
            } else {
                grid
            }
        }
        .navigationTitle(selected == nil
                         ? "汽水探索模式"
                         : (selected?["text"] as? String ?? "歌单"))
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .task { if scenes.isEmpty && auth.sodaBound { await loadModes() } }
    }

    // MARK: 模式网格
    @ViewBuilder
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(scenes.enumerated()), id: \.offset) { _, sc in
                    Button { Task { await openMode(sc) } } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            KXCover(url: APIClient.coverURL(sc["cover_url"] as? String, size: 260))
                                .aspectRatio(1.6, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 96)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(sc["text"] as? String ?? "未知模式")
                                .font(KXFont.scaled(13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .padding(.top, 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 120)
        }
    }

    // MARK: 某模式的歌单列表
    @ViewBuilder
    private func playlistList(for scene: [String: Any]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    selected = nil
                } label: {
                    HStack(spacing: 6) {
                        KXIcon(icon: .chevron, size: 13, color: .kxAccent)
                            .rotationEffect(.degrees(-90))
                        Text("返回全部模式").font(KXFont.scaled(13)).foregroundColor(.kxAccent)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                if loadingPlaylists {
                    ProgressView("加载歌单…").frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else if let err = playlistError {
                    Text(err).font(.subheadline).foregroundColor(.secondary)
                        .padding(24)
                } else if playlists.isEmpty {
                    Text("这个模式暂时没有歌单").font(.subheadline).foregroundColor(.secondary)
                        .padding(24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(playlists) { pl in
                            NavigationLink {
                                SodaPlaylistView(id: pl.id, name: pl.name, cover: pl.cover)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Color(.systemFill)
                                        KXCover(url: APIClient.coverURL(pl.cover, size: 120))
                                    }
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pl.name).font(KXFont.scaled(14, weight: .medium)).lineLimit(1)
                                        Text("\(pl.trackCount) 首").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    KXIcon(icon: .chevron, size: 14, color: .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: 数据
    private func loadModes() async {
        loading = true; errorMsg = nil
        do {
            scenes = try await APIClient.sodaModes()
            // 首页卡片带 initialSceneId 点入：定位到对应模式并直接展开歌单。
            if let target = initialSceneId,
               let found = scenes.first(where: { ($0["scene_mode_id"] as? String) == target }) {
                await openMode(found)
            }
        } catch {
            errorMsg = "无法加载听歌模式"
        }
        loading = false
    }

    private func openMode(_ scene: [String: Any]) async {
        guard let id = scene["scene_mode_id"] as? String, !id.isEmpty else { return }
        selected = scene
        loadingPlaylists = true; playlistError = nil; playlists = []
        do {
            playlists = try await APIClient.sodaModePlaylists(sceneModeId: id)
        } catch {
            playlistError = "无法加载该模式的歌单"
        }
        loadingPlaylists = false
    }

    private var notBoundView: some View {
        VStack(spacing: 12) {
            KXIcon(icon: .person, size: 40, color: .orange)
            Text("请先在「我的」页绑定汽水音乐").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            KXIcon(icon: .warning, size: 40, color: .orange)
            Text(msg).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("重试") { Task { await loadModes() } }
                .buttonStyle(.borderedProminent).tint(.kxAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
