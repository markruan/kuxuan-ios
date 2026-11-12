import SwiftUI
import UIKit

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
    @State private var showAccount = false
    @FocusState private var searchFocused: Bool
    @State private var dailySongs: [Song] = []
    @State private var ncmBound = false
    @State private var dailyChecked = false
    @State private var dailyLoading = false
    @State private var dailyError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                if let h = home {
                    if !h.hot.isEmpty { hotWords(h.hot) }
                    if !h.banners.isEmpty { bannerPager(h.banners) }
                    dailySection
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
            // 底部迷你播放条钉在物理底边后约 100pt 高，留出足够滚动余量
            .padding(.bottom, 120)
        }
        // 滚动首页即收起搜索键盘，不必先执行搜索才能退出来
        .scrollDismissesKeyboard(.immediately)
        // 数据回来时淡入，避免「加载中 → 整页内容」硬切
        .animation(.easeInOut(duration: 0.30), value: loading)
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
        .task { await load(); await loadDaily() }
        .refreshable { await load(); await loadDaily() }
        .sheet(isPresented: $showSearch) {
            SearchSheet(initialQuery: searchQuery) { songs, idx in
                player.playSongs(songs, index: idx)
                showSearch = false
            }
            .environmentObject(player)
            .environmentObject(auth)
        }
        .sheet(isPresented: $showAccount) {
            AccountCenterView()
                .environmentObject(player)
                .environmentObject(auth)
        }
    }

    // MARK: 顶部：搜索框（略窄）+ 右侧个人中心按钮，合并为同一行
    // 原来是「独立一行右对齐菜单按钮 + 下一行满宽搜索框」，白占一行且顶部显空。
    // 现在菜单按钮进搜索行右侧，搜索框自然收窄约 48pt；圆角卡片样式、
    // .padding(.top, 6) 与水平 16 边距都保留，不会把内容顶进状态栏。
    // 图标统一走 KXIcon（自绘），不再使用苹果 SF Symbols。
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { openSearch() } label: {
                    KXIcon(icon: .search, size: 17, color: .secondary)
                }
                .buttonStyle(.plain)
                TextField("搜索歌曲或歌手", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { openSearch() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        KXIcon(icon: .close, size: 16, color: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .kxCard(radius: 12, shadowRadius: 6)

            // 进入输入态后，右侧个人中心按钮临时换成「取消」：
            // 一键清空关键词 + 收键盘 + 退出编辑，不必先执行搜索才能脱身。
            if searchFocused || !searchText.isEmpty {
                Button { cancelSearch() } label: {
                    Text("取消").font(.subheadline)
                        .foregroundColor(.kxAccent)
                        .frame(width: 44, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Button { showAccount = true } label: {
                    KXIcon(icon: .menu, size: 18, color: .primary)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.18), value: searchFocused)
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
    // 根因：KXCover 里的 AsyncImage(scaledToFill) 没有显式 frame，在 ZStack 中会按
    // 原图 1080×400 的 intrinsic size 撑宽坐标系 —— clipShape 的圆角落到屏幕外、
    // 底部渐变和标题被裁，TabView 自带的 UIPageControl 又盖在图片底部，
    // 于是看起来「圆角被挡住、下面少一截」。与 v4 修 FullPlayer 背景是同一个坑。
    // 修法：Color 钉死 + 显式 width/height + clipped；系统分页点改为独立一行自制圆点；
    // 高度按原图 2.7:1 算，图片完整展示不裁切。
    @ViewBuilder
    private func bannerPager(_ banners: [Banner]) -> some View {
        let side: CGFloat = 16, pageGap: CGFloat = 6
        let cardW = UIScreen.main.bounds.width - side * 2 - pageGap
        let cardH = round(cardW / 2.7)               // 1080×400 原图比例
        VStack(spacing: 10) {
            TabView(selection: $bannerIndex) {
                ForEach(Array(banners.enumerated()), id: \.offset) { i, b in
                    bannerCard(b, w: cardW, h: cardH)
                        .padding(.horizontal, pageGap / 2)
                        .tag(i)
                }
            }
            // .never：系统 UIPageControl 不再压在图片底部
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardH)

            // 自制分页点：独立一行，不遮挡卡片
            HStack(spacing: 6) {
                ForEach(banners.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == bannerIndex ? Color.kxAccent : Color.secondary.opacity(0.32))
                        .frame(width: i == bannerIndex ? 16 : 6, height: 6)
                }
            }
            .frame(height: 8)
            .animation(.easeInOut(duration: 0.25), value: bannerIndex)
        }
        .padding(.horizontal, side)
        .onAppear { if bannerIndex >= banners.count { bannerIndex = 0 } }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            guard banners.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                bannerIndex = (bannerIndex + 1) % banners.count
            }
        }
    }

    private func bannerCard(_ b: Banner, w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(.systemFill)                        // 无 intrinsic size，先钉死坐标系
            KXCover(url: APIClient.coverURL(b.img))
                .frame(width: w, height: h)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .frame(width: w, height: h)
                .allowsHitTesting(false)
            Text(b.title).font(.caption.bold()).foregroundColor(.white)
                .lineLimit(1).padding(12)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
    }

    // MARK: 推荐歌单：每页 3 列 × 2 行 = 6 个，多出的靠左滑翻页
    // 单元格用「显式 width/height」钉死封面正方形，而不是让 scaledToFill 的图片
    // 自己决定尺寸 —— 这是之前第二行图片重叠的根因，分页后更不能有弹性行高。
    // MARK: 推荐歌单（横向画廊轮播，参考「推荐专辑」堆叠卡片样式）
    private func recommendSection(_ playlists: [Playlist]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("推荐歌单",
                         subtitle: playlists.count > 0 ? "\(playlists.count) 个精选 · 左右滑动浏览" : "\(playlists.count) 个精选")
            GalleryCarousel(playlists: playlists)
        }
    }

    /// 横向画廊轮播（参考 ACarousel / AtlysAssignment 的 center-zoom 模式）
    /// 每张卡片内嵌 GeometryReader，实时读取「自身中心距视口中心的距离」来算缩放与透明度，
    /// 不依赖全局 offset 公式、不受外层 padding 偏移影响；缩放直接跟随滚动，连续丝滑。
    /// 视觉：中心卡片 1.0、相邻收敛到 ~0.72、更远 ~0.65，缩放/压暗过渡平缓，中心仍突出；
    /// 两侧卡片更大更可见，一屏能同时露出更多卡片（中心 + 两侧各约 2 张）。
    /// 默认第二条居中最大（进页面滚到 index 1）；整体高度紧凑，卡片偏小避免占用过多空间。
    private struct GalleryCarousel: View {
        let playlists: [Playlist]
        private let cardW: CGFloat = 130
        private let spacing: CGFloat = 6
        private let slotH: CGFloat = 176   // 封面(130) + 间距6 + 标题14 + 描述11 + 余量

        var body: some View {
            GeometryReader { geo in
                let viewportW = geo.size.width
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(Array(playlists.enumerated()), id: \.element.id) { _, pl in
                                galleryCard(pl, viewportW: viewportW)
                                    .frame(width: cardW, height: slotH)
                            }
                        }
                        .padding(.horizontal, (viewportW - cardW) / 2)
                    }
                    .coordinateSpace(name: "gallery")
                    .onAppear {
                        // 默认第二条居中最大（至少 2 个才生效），关闭动画避免进场跳动。
                        if playlists.count > 1 {
                            proxy.scrollTo(playlists[1].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: slotH)
        }

        private func galleryCard(_ pl: Playlist, viewportW: CGFloat) -> some View {
            GeometryReader { g in
                let midX = g.frame(in: .named("gallery")).midX
                let dist = abs(midX - viewportW / 2)
                // 距中心越近越大：中心 1.0，相邻卡片收敛到 0.55；两侧明显缩小并压暗，
                // 让视口内同时露出更多卡片（中心 + 两侧各约 2 张）。
                // 距中心越近越大：中心 1.0，相邻收敛到 ~0.72、更远 ~0.65；缩放/压暗过渡
                // 平缓（相比此前相邻直接掉到 0.55 的硬落差），让两侧卡片更大更可见、
                // 视口内同时露出更多卡片，且中心仍明显突出。
                let t = min(dist / (cardW * 1.3), 1)
                let scale = 1 - t * 0.35
                let opacity = 1 - t * 0.30
                NavigationLink(value: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover)) {
                    VStack(spacing: 6) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(pl.cover, size: 260))
                        }
                        .frame(width: cardW, height: cardW)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                        Text(pl.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(width: cardW)
                        Text(pl.description.isEmpty ? " " : pl.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(width: cardW)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .opacity(opacity)
            }
        }
    }

    // MARK: 榜单（封面左下不再叠数字名次角标）
    @ViewBuilder
    private func chartSection(_ charts: [Chart]) -> some View {
        sectionTitle("排行榜", subtitle: "实时更新")
        VStack(spacing: 10) {
            ForEach(charts) { c in
                NavigationLink(value: PlaylistRef(id: c.id, name: c.name, cover: c.cover)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(c.cover, size: 140))
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name).font(.subheadline.bold())
                            Text(c.tracks.prefix(3).map { $0.title }.joined(separator: " / "))
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        KXIcon(icon: .chevron, size: 15, color: .secondary)
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
                            KXCover(url: APIClient.coverURL(s.cover, size: 120))
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(.subheadline).lineLimit(1)
                            Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        KXIcon(icon: .play, size: 20, color: .kxAccent.opacity(0.7))
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

    // MARK: 每日推荐（网易云每日歌曲推荐）
    // 后端优先用已绑定账号的个性化推荐，账号无推荐时回退上游默认推荐，
    // 因此无论是否绑定都能拿到一组每日歌曲。横向卡片轨道 + 「播放全部」。
    @ViewBuilder
    private var dailySection: some View {
        if !dailyChecked {
            EmptyView()
        } else if dailyLoading && dailySongs.isEmpty {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("加载每日推荐…").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
        } else if let err = dailyError, dailySongs.isEmpty {
            HStack(spacing: 6) {
                KXIcon(icon: .warning, size: 16, color: .secondary)
                Text(err).font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
        } else if dailySongs.isEmpty {
            if !ncmBound { bindPrompt }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("每日推荐").font(.headline)
                    Text("\(dailySongs.count) 首").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        player.playSongs(dailySongs, index: 0)
                    } label: {
                        HStack(spacing: 4) {
                            KXIcon(icon: .play, size: 12, color: .white)
                            Text("播放全部").font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.kxAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(dailySongs.enumerated()), id: \.element.id) { i, s in
                            dailyCard(s, index: i)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func dailyCard(_ s: Song, index: Int) -> some View {
        Button {
            player.playSongs(dailySongs, index: index)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color(.systemFill)
                    KXCover(url: APIClient.coverURL(s.cover, size: 240))
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(s.title).font(.caption).lineLimit(2)
                    .foregroundColor(.primary)
                    .frame(width: 110, height: 30, alignment: .top)
                Text(s.artist).font(.system(size: 9))
                    .foregroundColor(.secondary).lineLimit(1)
                    .frame(width: 110, height: 12, alignment: .top)
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
    }

    private var bindPrompt: some View {
        Button {
            showAccount = true
        } label: {
            HStack(spacing: 12) {
                KXIcon(icon: .note, size: 22, color: .kxAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("开启每日歌曲推荐").font(.subheadline.bold())
                    Text("绑定网易云账号后，为你精准推荐").font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("去绑定").font(.caption).foregroundColor(.kxAccent)
            }
            .padding(12).kxCard(radius: 12, shadowRadius: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func loadDaily() async {
        dailyLoading = true
        dailyError = nil
        defer { dailyLoading = false; dailyChecked = true }
        do {
            if let me = try? await APIClient.ncmMe() {
                ncmBound = me.bound
            }
            dailySongs = try await APIClient.ncmDailyRecommend()
        } catch {
            dailySongs = []
            dailyError = "每日推荐加载失败"
        }
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
            KXIcon(icon: .warning, size: 42, color: .secondary)
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
        catch { errorMsg = "无法连接服务器\n请确认网络畅通、后端服务正在运行" }
        loading = false
    }

    private func openSearch() {
        // 先收键盘，避免键盘与 sheet 叠加导致搜索页被顶起、关闭按钮够不到
        searchFocused = false
        searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        showSearch = true
    }

    /// 取消搜索输入态：清空关键词、收键盘、把右侧「取消」还原成个人中心按钮
    private func cancelSearch() {
        searchText = ""
        searchQuery = ""
        searchFocused = false
    }
}

// MARK: - 搜索页
// 三个分类：歌曲 / 歌手 / 歌单。歌手与歌单结果可点进二级页（各自 NavigationLink），
// 歌曲结果点按即播并关闭 sheet（沿用 onPlay 回调），与首页播放体验一致。
struct SearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let initialQuery: String
    let onPlay: ([Song], Int) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case songs = "歌曲", artists = "歌手", playlists = "歌单"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var tab: Tab = .songs
    @State private var songs: [Song] = []
    @State private var artists: [NCMArtist] = []
    @State private var playlists: [NCMSearchPlaylist] = []
    @State private var loading = false
    @State private var searched = false
    @State private var lastQuery = ""
    @State private var err: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    KXIcon(icon: .search, size: 17, color: .secondary)
                    TextField("搜索歌曲 / 歌手 / 歌单", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            KXIcon(icon: .close, size: 16, color: .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("搜索") { Task { await runSearch() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.kxAccent)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))

                Picker("类型", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                Divider()
                content
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.kxAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(.kxAccent)
                }
            }
            // 滚动结果列表时顺带收键盘；sheet 保持可下滑关闭
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(false)
            .task {
                query = initialQuery
                if !query.isEmpty { await runSearch() }
            }
            .onChange(of: tab) { _ in
                if !query.isEmpty { Task { await runSearch() } }
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
                KXIcon(icon: .warning, size: 40, color: .secondary)
                Text(e).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("重试") { Task { await runSearch() } }
                    .buttonStyle(.borderedProminent).tint(.kxAccent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            VStack(spacing: 12) {
                KXIcon(icon: .search, size: 40, color: .secondary)
                Text(emptyText)
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tab == .songs {
            List(Array(songs.enumerated()), id: \.element.id) { i, s in
                Button { onPlay(songs, i) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(s.cover, size: 120))
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
        } else if tab == .artists {
            List(artists) { a in
                NavigationLink {
                    ArtistSongsView(artist: a)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(a.cover, size: 120))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.name).font(.subheadline).lineLimit(1)
                            Text("\(a.musicSize) 首单曲").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            .listStyle(.plain)
        } else {
            List(playlists) { p in
                NavigationLink {
                    PlaylistView(ref: PlaylistRef(id: p.id, name: p.name, cover: p.cover))
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Color(.systemFill)
                            KXCover(url: APIClient.coverURL(p.cover, size: 120))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.subheadline).lineLimit(1)
                            Text("\(p.trackCount) 首 · 播放 \(p.playCountText)" + (p.creator.isEmpty ? "" : " · \(p.creator)"))
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            .listStyle(.plain)
        }
    }

    private var isEmpty: Bool {
        switch tab {
        case .songs: return songs.isEmpty
        case .artists: return artists.isEmpty
        case .playlists: return playlists.isEmpty
        }
    }

    private var emptyText: String {
        let q = lastQuery.isEmpty ? "该关键词" : "「\(lastQuery)」"
        switch tab {
        case .songs: return searched ? "没有找到\(q)相关歌曲" : "输入歌曲名或歌手，点「搜索」"
        case .artists: return searched ? "没有找到\(q)相关歌手" : "输入歌手名，点「搜索」"
        case .playlists: return searched ? "没有找到\(q)相关歌单" : "输入歌单名，点「搜索」"
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        lastQuery = q
        loading = true
        err = nil
        do {
            switch tab {
            case .songs:
                songs = try await APIClient.search(q: q)
                artists = []; playlists = []
            case .artists:
                artists = try await APIClient.searchArtists(q: q)
                songs = []; playlists = []
            case .playlists:
                playlists = try await APIClient.searchPlaylists(q: q)
                songs = []; artists = []
            }
            searched = true
        } catch {
            songs = []; artists = []; playlists = []
            searched = true
            err = "搜索失败：\(error.localizedDescription)\n请确认 Mac 上 server.py 已启动、手机与 Mac 处于同一 Wi-Fi"
        }
        loading = false
    }
}

// MARK: - 歌手热门歌曲页（搜索歌手后进入，展示并播放该歌手热门歌曲）
struct ArtistSongsView: View {
    @EnvironmentObject var player: PlayerEngine
    let artist: NCMArtist
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var err: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("加载中…")
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
            } else if songs.isEmpty {
                VStack(spacing: 12) {
                    KXIcon(icon: .note, size: 40, color: .secondary)
                    Text("该歌手暂无可用歌曲").font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(songs.enumerated()), id: \.element.id) { i, s in
                    Button { player.playSongs(songs, index: i) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Color(.systemFill)
                                KXCover(url: APIClient.coverURL(s.cover, size: 120))
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
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
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .task { await load() }
    }

    private func load() async {
        loading = true; err = nil
        do {
            let (list, _) = try await APIClient.artistSongs(id: artist.id)
            songs = list
        } catch {
            err = "歌手歌曲加载失败：\(error.localizedDescription)"
        }
        loading = false
    }
}
