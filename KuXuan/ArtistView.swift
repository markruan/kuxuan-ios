import SwiftUI

/// 歌手页（中等丰富度）入口：由 RootView 的 fullScreenCover(item: $player.artistToShow) 承接。
///
/// 点「相似歌手」不再用 NavigationStack(path:) push：push 会额外叠一层系统返回箭头，
/// 和自定义「关闭」「返回上一个歌手」凑成三个返回控件，且要逐层 pop 才能退出浮层。
/// 改为**同一个页面内替换当前歌手**：内部只维护一个歌手栈，浮层永远只有一层。
///  · 根歌手：左上只有「关闭歌手页」
///  · 下钻后：左上「返回上一个歌手」+ 右上「关闭」（任意深度都能一步退出浮层）
/// 顶部下滑手势始终是「关闭整个歌手页」，与栈深无关。
struct ArtistView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let mini: MiniArtist

    /// 已下钻的歌手（不含根歌手 mini）。栈顶即当前展示的歌手。
    @State private var stack: [MiniArtist] = []

    private var current: MiniArtist { stack.last ?? mini }

    var body: some View {
        ArtistDetailContent(
            mini: current,
            canGoBack: !stack.isEmpty,
            onBack: { if !stack.isEmpty { stack.removeLast() } },
            onClose: { player.artistToShow = nil },
            onOpenArtist: { a in
                // 点回根歌手 / 已访问过的歌手时直接回到那一层，避免 A→B→A 无限加深，
                // 也避免用户为了退出而反复按返回。
                if a.id == mini.id {
                    stack = []
                } else if let idx = stack.firstIndex(where: { $0.id == a.id }) {
                    stack = Array(stack.prefix(through: idx))
                } else {
                    stack.append(a)
                }
            }
        )
        // 换歌手时重建正文：@State（详情/歌曲/滚动态）随之重置，.task 重新拉数据。
        .id(current.id)
        // 收藏歌手的提示浮层：歌手页是全屏浮层，会盖住播放页的 toast，这里单独挂一份
        .overlay(alignment: .top) {
            FavSyncToast().padding(.top, 52)
        }
        // fullScreenCover 不自带下拉关闭：顶部指示条提供一条**可发现**的下滑关闭路径。
        // 手势只挂在指示条 20pt 区域，不与内部 ScrollView 的滚动竞争。
        .overlay(alignment: .top) {
            KXModalGrabber()
                .kxModalDismiss(isPresented: Binding<Bool>(
                    get: { player.artistToShow != nil },
                    set: { if !$0 { player.artistToShow = nil } }))
        }
    }
}

/// 歌手页正文：头部大封面 + 名 + 单曲/专辑数 + ♡收藏 + 播放全部；
/// 热门歌曲列表；相似歌手横向；专辑横向；可展开简介。
struct ArtistDetailContent: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let mini: MiniArtist
    /// 是否处于下钻层（决定左上按钮是「返回」还是「关闭」）
    let canGoBack: Bool
    let onBack: () -> Void
    let onClose: () -> Void
    let onOpenArtist: (MiniArtist) -> Void

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
                        KXArtistSkeleton()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.horizontal, 16)
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

    // MARK: 顶部栏：始终只有一个「返回/关闭」主按钮；下钻层额外给一个明确的「关闭」
    /// 主按钮语义随层级变化，避免同屏出现多个返回箭头；右侧的「关闭」不是返回，
    /// 无论下钻多少层都能一步退出整个歌手浮层。
    private var topBar: some View {
        HStack(spacing: 12) {
            if canGoBack {
                KXIconButton(icon: .chevronLeft, label: "返回上一个歌手",
                             hint: "回到刚才的歌手页", size: 20, color: .primary) {
                    onBack()
                }
            } else {
                KXModalCloseButton(label: "关闭歌手页", hint: "返回播放页", color: .primary) {
                    onClose()
                }
            }
            Spacer()
            if canGoBack {
                KXIconButton(icon: .close, label: "关闭歌手页",
                             hint: "退出整个歌手页，返回播放页", size: 18, color: .primary) {
                    onClose()
                }
            }
        }
        .padding(.horizontal, 8)
        // 顶部 24pt 让位给「下拉关闭」指示条（overlay 占 0~20pt），
        // 否则指示条的拖拽热区会盖住关闭按钮上半部分。
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            actions
            // 歌手简介放最前（可折叠），符合「简介 → 专辑 → 歌曲」的浏览顺序
            if !bioText.isEmpty { bioSection }
            // 专辑（封面 + 专辑名，横向）
            if !albums.isEmpty { albumsSection }
            // 相似歌手（横向圆形头像，可点下钻到另一个歌手页）
            if !similar.isEmpty { similarSection }
            // 热门歌曲列表紧随其后，作为歌手页主体
            songSection
            Spacer(minLength: 60)
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
                .frame(minHeight: 44)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(faved ? "取消收藏歌手" : "收藏歌手")
            .accessibilityValue(faved ? "已收藏" : "未收藏")

            Button {
                guard !songs.isEmpty else { return }
                player.playSongs(songs, index: 0)
                onClose()   // 收起歌手页，露出全屏播放器
            } label: {
                HStack(spacing: 6) {
                    KXIcon(icon: .play, size: 16, color: .white)
                    Text("播放全部").font(.subheadline.bold())
                }
                .padding(.horizontal, 18).padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.kxAccent))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放全部歌曲")
        }
    }

    // MARK: 热门歌曲（歌手页主体：始终展示，空时给占位，不隐藏「歌曲列表」区块）
    private var songSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("热门歌曲 \(songs.count)")
            if songs.isEmpty {
                Text("暂无热门歌曲")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                        Button {
                            player.playSongs(songs, index: i)
                            onClose()
                        } label: {
                            HStack(spacing: 12) {
                                KXCover(url: APIClient.coverURL(s.cover, size: 120))
                                    .frame(width: 46, height: 46).cornerRadius(6)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.title).font(KXFont.scaled(15, weight: .medium)).lineLimit(1)
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
    }

    // MARK: 相似歌手（横向）
    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("相似歌手")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(similar) { a in
                        Button { onOpenArtist(a) } label: {
                            VStack(spacing: 6) {
                                KXCover(url: APIClient.coverURL(a.cover, size: 140))
                                    .frame(width: 74, height: 74)
                                    .clipShape(Circle())
                                Text(a.name).font(.caption).lineLimit(1)
                                    .frame(width: 74)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看相似歌手 \(a.name)")
                        .accessibilityHint("在当前歌手页切换，不会新开一层页面")
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
