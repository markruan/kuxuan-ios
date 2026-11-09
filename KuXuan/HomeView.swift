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
    @State private var searchResults: [Song] = []
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
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
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
        .searchable(text: $searchText, prompt: "搜索歌曲或歌手")
        .onSubmit(of: .search) { Task { await doSearch() } }
        .sheet(isPresented: $showSearch) { SearchResults(results: searchResults) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(player) }
    }

    // MARK: 顶部
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KuXuan").font(.title.bold())
                Text(home?.statusText ?? "云音乐 · 在线音源")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3).foregroundColor(.primary)
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
                    .padding(10).background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
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
                    .padding(8).background(Color(.secondarySystemGroupedBackground)).cornerRadius(10)
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
    private func doSearch() async {
        guard !searchText.isEmpty else { return }
        do { searchResults = try await APIClient.search(q: searchText) }
        catch { searchResults = [] }
        showSearch = true
    }
}

// 搜索结果
struct SearchResults: View {
    @EnvironmentObject var player: PlayerEngine
    let results: [Song]
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(results) { s in
                Button {
                    player.playSongs(results, index: results.firstIndex(of: s) ?? 0)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(s.title).font(.subheadline)
                        Text(s.artist).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("搜索结果")
            .toolbar { Button("关闭") { dismiss() } }
            .listStyle(.insetGrouped)
        }
    }
}
