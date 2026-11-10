import SwiftUI

// 封面图通用组件（多页面复用）
struct KXCover: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Color(.systemFill)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var player: PlayerEngine
    @State private var home: HomeResp?
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var bannerIndex = 0
    @State private var searchText = ""
    @State private var searchQuery = ""
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchBar
                if let h = home {
                    if !h.banners.isEmpty { bannerPager(h.banners) }
                    if !h.playlists.isEmpty { recommendSection(h.playlists) }
                    if !h.charts.isEmpty { chartSection(h.charts) }
                    if !h.newsongs.isEmpty { newSongSection(h.newsongs) }
                } else if loading {
                    ProgressView("加载中…").frame(maxWidth: .infinity, alignment: .center).padding(.top, 80)
                } else if errorMsg != nil {
                    errorView
                }
            }
            .padding(.bottom, 90)
        }
        .background(
            Color(.systemGroupedBackground)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Color.kxBrand1.opacity(0.20), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                }
                .ignoresSafeArea()
        )
        // 不能对 ScrollView 加 ignoresSafeArea(edges: .top)：
        // 会让「KuXuan」标题和设置齿轮顶进状态栏。背景单独延伸即可。
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showSearch) {
            SearchSheet(initialQuery: searchQuery) { songs, idx in
                player.playSongs(songs, index: idx)
                showSearch = false
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(player) }
    }

    // MARK: 搜索栏（自定义，避免 .searchable 在隐藏导航栏下错位渲染到屏幕底部）
    private var searchBar: some View {
        HStack(spacing: 8) {
            Button { openSearch() } label: {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            }
            TextField("搜索歌曲或歌手", text: $searchText)
                .submitLabel(.search)
                .onSubmit { openSearch() }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .kxCard(radius: 12, shadowRadius: 6)
        .padding(.horizontal, 16)
    }

    // MARK: 顶部
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KuXuan").font(.title.bold()).foregroundStyle(LinearGradient.kx)
                Text(home?.statusText ?? "云音乐 · 在线音源")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3).foregroundColor(.kxAccent)
                    .padding(8).background(Color(.secondarySystemFill)).clipShape(Circle())
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    // MARK: Banner（自动轮播 + 顶部留白）
    @ViewBuilder
    private func bannerPager(_ banners: [Banner]) -> some View {
        TabView(selection: $bannerIndex) {
            ForEach(Array(banners.enumerated()), id: \.offset) { i, b in
                KXCover(url: APIClient.coverURL(b.img))
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 150)
        .padding(.horizontal, 16)
        .padding(.top, 12)                  // 与顶部标题留白
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard banners.count > 1 else { return }
            withAnimation { bannerIndex = (bannerIndex + 1) % banners.count }
        }
    }

    // MARK: 推荐歌单（正方形网格）
    @ViewBuilder
    private func recommendSection(_ playlists: [Playlist]) -> some View {
        sectionTitle("推荐歌单")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(playlists) { pl in
                NavigationLink(value: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover)) {
                    VStack(alignment: .leading, spacing: 6) {
                        KXCover(url: APIClient.coverURL(pl.cover))
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                        Text(pl.name).font(.caption).lineLimit(1).foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 榜单
    @ViewBuilder
    private func chartSection(_ charts: [Chart]) -> some View {
        sectionTitle("排行榜")
        VStack(spacing: 10) {
            ForEach(charts) { c in
                NavigationLink(value: PlaylistRef(id: c.id, name: c.name, cover: c.cover)) {
                    HStack(spacing: 12) {
                        KXCover(url: APIClient.coverURL(c.cover))
                            .frame(width: 56, height: 56).cornerRadius(8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(.subheadline.bold())
                            Text(c.tracks.prefix(3).map { $0.title }.joined(separator: " / "))
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .padding(10).kxCard(radius: 12, shadowRadius: 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 新歌
    @ViewBuilder
    private func newSongSection(_ songs: [Song]) -> some View {
        sectionTitle("新歌速递")
        VStack(spacing: 8) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                Button {
                    player.playSongs(songs, index: i)
                } label: {
                    HStack(spacing: 12) {
                        KXCover(url: APIClient.coverURL(s.cover))
                            .frame(width: 46, height: 46).cornerRadius(8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.subheadline).lineLimit(1)
                            Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8).kxCard(radius: 10, shadowRadius: 6)
                }
                .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.headline).padding(.horizontal, 16)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
            Text(errorMsg ?? "加载失败").font(.subheadline).foregroundColor(.secondary)
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(.kxAccent)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    // MARK: 数据
    private func load() async {
        loading = true; errorMsg = nil
        do { home = try await APIClient.home() }
        catch { errorMsg = "无法连接服务器（\(APIClient.baseURL)）\n请确认 Mac 上 server.py 已启动、手机与 Mac 同一 Wi-Fi" }
        loading = false
    }
    // 只负责把关键词交给搜索页，网络请求与状态展示全部在 SearchSheet 内完成，
    // 避免请求失败时拿到空数组、弹出一个没有任何提示的白屏。
    private func openSearch() {
        searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        showSearch = true
    }
}

// MARK: - 搜索页
// 注意：.sheet 呈现的视图不会自动继承父视图的 @EnvironmentObject，
// 所以这里不声明 @EnvironmentObject，改用 onPlay 闭包回调，避免白屏/崩溃。
struct SearchSheet: View {
    @Environment(\.dismiss) var dismiss
    let initialQuery: String
    let onPlay: ([Song], Int) -> Void

    @State private var query = ""
    @State private var results: [Song] = []
    @State private var loading = false
    @State private var searched = false
    @State private var lastQuery = ""
    @State private var err: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索歌曲或歌手", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                    Button("搜索") { Task { await runSearch() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.kxAccent)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                Divider()
                content
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                query = initialQuery
                if !query.isEmpty { await runSearch() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 12) {
                ProgressView()
                Text("搜索中…").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = err {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundColor(.secondary)
                Text(e).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("重试") { Task { await runSearch() } }
                    .buttonStyle(.borderedProminent).tint(.kxAccent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
                Text(searched ? "没有找到「\(lastQuery)」相关歌曲" : "输入歌曲名或歌手，点「搜索」")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(Array(results.enumerated()), id: \.element.id) { i, s in
                Button { onPlay(results, i) } label: {
                    HStack(spacing: 12) {
                        KXCover(url: APIClient.coverURL(s.cover))
                            .frame(width: 44, height: 44).cornerRadius(6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.subheadline).lineLimit(1)
                            Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            .listStyle(.plain)
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        lastQuery = q
        loading = true
        err = nil
        do {
            results = try await APIClient.search(q: q)
            searched = true
        } catch {
            results = []
            searched = true
            err = "搜索失败：\(error.localizedDescription)\n请确认 Mac 上 server.py 已启动、手机与 Mac 处于同一 Wi‑Fi"
        }
        loading = false
    }
}
