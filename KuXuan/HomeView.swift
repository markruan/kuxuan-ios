import SwiftUI

// 封面图通用组件（多页面复用）
// 关键：scaledToFill 的图片必须被 .clipped() 约束，否则会按原图像素撑开父视图，
// 在 LazyVGrid 中把行高顶坏，导致第二行图片与第一行重叠。
struct KXCover: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Color(.systemFill)
            }
        }
        .clipped()
    }
}

struct HomeView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    @State private var home: HomeResp?
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var bannerIndex = 0
    @State private var searchText = ""
    @State private var searchQuery = ""
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchBar
                if let h = home {
                    if !h.hot.isEmpty { hotWords(h.hot) }
                    if !h.banners.isEmpty { bannerPager(h.banners) }
                    if !h.playlists.isEmpty { recommendSection(h.playlists) }
                    if !h.charts.isEmpty { chartSection(h.charts) }
                    if !h.newsongs.isEmpty { newSongSection(h.newsongs) }
                    statusFooter(h)
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
                    LinearGradient(colors: [Color.kxBrand1.opacity(0.22),
                                            Color.kxBrand2.opacity(0.08), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 280)
                }
                .ignoresSafeArea()
        )
        // 不对 ScrollView 加 ignoresSafeArea(edges:.top)：会把标题顶进状态栏。
        .navigationBarHidden(true)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showSearch) {
            SearchSheet(initialQuery: searchQuery) { songs, idx in
                player.playSongs(songs, index: idx)
                showSearch = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(player).environmentObject(auth)
        }
        .sheet(isPresented: $showAccount) {
            AccountCenterView()
                .environmentObject(player)
                .environmentObject(auth)
        }
    }

    // MARK: 顶部
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { showAccount = true } label: {
                ZStack {
                    Circle().fill(LinearGradient.kx)
                    if let a = auth.ncmProfile?.avatar, !a.isEmpty {
                        AsyncImage(url: APIClient.proxiedPicURL(a)) { phase in
                            if case .success(let im) = phase {
                                im.resizable().scaledToFill().clipShape(Circle())
                            }
                        }
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 17)).foregroundColor(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("KuXuan").font(.title2.bold()).foregroundStyle(LinearGradient.kx)
                Text(home?.statusText ?? "云音乐 · 在线音源")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { showAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3).foregroundColor(.kxAccent)
                    .padding(8).background(Color(.secondarySystemFill)).clipShape(Circle())
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3).foregroundColor(.kxAccent)
                    .padding(8).background(Color(.secondarySystemFill)).clipShape(Circle())
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    // MARK: 搜索栏
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

    // MARK: 热搜词（后端 home.hot，之前完全没用起来）
    private func hotWords(_ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热门搜索").font(.caption.bold()).foregroundColor(.secondary)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        Button {
                            searchText = w
                            openSearch()
                        } label: {
                            HStack(spacing: 4) {
                                if i < 3 {
                                    Text("\(i + 1)").font(.caption2.bold())
                                        .foregroundColor(.kxAccent)
                                }
                                Text(w).font(.caption).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                        }
                        .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Banner
    @ViewBuilder
    private func bannerPager(_ banners: [Banner]) -> some View {
        TabView(selection: $bannerIndex) {
            ForEach(Array(banners.enumerated()), id: \.offset) { i, b in
                ZStack(alignment: .bottomLeading) {
                    KXCover(url: APIClient.coverURL(b.img))
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .center, endPoint: .bottom)
                    Text(b.title).font(.caption.bold()).foregroundColor(.white)
                        .lineLimit(1).padding(10)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 150)
        .padding(.horizontal, 16)
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            guard banners.count > 1 else { return }
            withAnimation { bannerIndex = (bannerIndex + 1) % banners.count }
        }
    }

    // MARK: 推荐歌单
    // 修复第二行重叠：用「无 intrinsic size 的 Color + aspectRatio(1,.fit)」先钉死
    // 单元格高度 = 列宽，再把封面放进 overlay 并 clipped。原写法让 scaledToFill
    // 的图片自己决定高度，行高被撑大后图片溢出到下一行。
    @ViewBuilder
    private func recommendSection(_ playlists: [Playlist]) -> some View {
        sectionTitle("推荐歌单", subtitle: "\(playlists.count) 个精选")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
            ForEach(playlists) { pl in
                NavigationLink(value: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(pl.cover))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) {
                            if pl.playCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "play.fill").font(.system(size: 7))
                                    Text(pl.playCountText).font(.system(size: 9))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .padding(5)
                            }
                        }
                        Text(pl.name).font(.caption).lineLimit(2)
                            .foregroundColor(.primary)
                            .frame(height: 30, alignment: .top)
                        if !pl.description.isEmpty {
                            Text(pl.description).font(.system(size: 9))
                                .foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 榜单
    @ViewBuilder
    private func chartSection(_ charts: [Chart]) -> some View {
        sectionTitle("排行榜", subtitle: "实时更新")
        VStack(spacing: 10) {
            ForEach(Array(charts.enumerated()), id: \.element.id) { i, c in
                NavigationLink(value: PlaylistRef(id: c.id, name: c.name, cover: c.cover)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(c.cover))
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(alignment: .bottomLeading) {
                            Text("\(i + 1)").font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.kxAccent.opacity(0.9))
                                .clipShape(Capsule())
                                .padding(3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
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
        sectionTitle("新歌速递", subtitle: "\(songs.count) 首")
        VStack(spacing: 8) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                Button {
                    player.playSongs(songs, index: i)
                } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(.caption2.bold()).foregroundColor(.kxAccent)
                            .frame(width: 22)
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(s.cover))
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.subheadline).lineLimit(1)
                            Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.circle").foregroundColor(.kxAccent.opacity(0.7))
                    }
                    .padding(8).kxCard(radius: 10, shadowRadius: 6)
                }
                .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func statusFooter(_ h: HomeResp) -> some View {
        HStack(spacing: 6) {
            Circle().fill(h.online ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text("音源状态：\(h.statusText)")
            Spacer()
            Text("\(h.playlists.count) 歌单 · \(h.newsongs.count) 新歌")
        }
        .font(.caption2).foregroundColor(.secondary)
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private func sectionTitle(_ t: String, subtitle: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
            Text(errorMsg ?? "加载失败").font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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

    private func openSearch() {
        searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        showSearch = true
    }
}

// MARK: - 搜索页
// .sheet 不自动继承 @EnvironmentObject，所以这里不用环境对象，改用闭包回调。
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
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(s.cover))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            err = "搜索失败：\(error.localizedDescription)\n请确认 Mac 上 server.py 已启动、手机与 Mac 处于同一 Wi-Fi"
        }
        loading = false
    }
}
