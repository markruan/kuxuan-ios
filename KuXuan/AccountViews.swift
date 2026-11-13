import SwiftUI
import UIKit

// MARK: - 个人中心（首页搜索栏右侧三横线按钮进入，自带 NavigationStack）
// 整理原则：
//  1) 颜色只保留一套品牌色：所有列表图标统一 .kxAccent，状态文字统一 .secondary，
//     强调数值用 .kxAccent；只有「解绑」的文字沿用 iOS destructive 的系统红。
//     不再混用 green / orange / 图标各色，避免整页花。
//  2) 按「是什么」而不是「从哪来」分组：音乐内容、歌单、账号同步、设置、服务状态各自成段；
//     我创建的歌单从「网易云账号」移到「我的歌单」，服务状态不再和设置挤在一起。
//  3) 图标全部走 KXIcon / KXLabel 自绘体系，不使用苹果 SF Symbols。
struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: PlayerEngine
    /// 关闭整个「个人中心」sheet 的回调（由 HomeView 用 showAccount=false 传入）。
    /// 注意：从被 push 进来的 ArtistFavPage 里直接调用 @Environment(.dismiss) 只会 pop 掉
    /// 导航层级、关不掉 sheet，导致歌手页 fullScreenCover 与 sheet 同层冲突（闪屏/返回落错页）。
    /// 因此点歌手必须用这个回调关掉 sheet（与 SearchSheet 用 showSearch=false 是同一套可靠机制）。
    let onClose: () -> Void

    @State private var showQR = false
    @State private var infoMessage: String?
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section { profileHeader }

                Section("我的收藏") { myFavSection }

                Section("最近播放") { recentSection }

                Section {
                    playlistSection
                } header: {
                    Text("我的歌单")
                } footer: {
                    Text("我创建的歌单保存在网易云账号里，在网易云 App 也能看到。")
                        .font(.caption2)
                }

                Section {
                    ncmSection
                } header: {
                    Text("网易云账号")
                } footer: {
                    Text("登录后，收藏的歌曲会保存到网易云「我喜欢的音乐」，也可新建与管理歌单。")
                        .font(.caption2)
                }

                Section("设置") { settingsSection }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await load() } }
            }
            .sheet(isPresented: $showQR) {
                NCMQRView().environmentObject(auth)
            }
            // 故意不注册 navigationDestination(for: PlaylistRef.self)：
            // 值驱动 destination 若只挂在根 List 上，从被 push 的第二层页面（收藏歌单列表）
            // 触发 NavigationLink(value:) 会解析不到 destination，跳转被挂起，
            // 直到 pop 回根 List 才补执行 —— 即用户反馈的「点歌单闪一下没反应、退出列表才出来」。
            // 个人中心内所有歌单入口统一改用 NavigationLink { PlaylistView(...) } 闭包形式
            // （与搜索页歌单一致），点击即 push，不依赖 destination 注册层级。
            .alert("提示", isPresented: Binding<Bool>(
                get: { infoMessage != nil },
                set: { if !$0 { infoMessage = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text(infoMessage ?? "")
            }
        }
    }

    private func load() async {
        await auth.refresh()
        if auth.ncmBound {
            await player.syncFavsFromCloud()
            await player.syncFavArtistsFromCloud()
        }
    }

    // MARK: 资料卡
    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.kx)
                if let img = avatarURL {
                    KXCachedImage(url: img, placeholder: nil)
                        .clipShape(Circle())
                } else {
                    KXIcon(icon: .person, size: 30, color: .white)
                }
            }
            .frame(width: 62, height: 62)
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

            VStack(alignment: .leading, spacing: 6) {
                Text(auth.ncmProfile?.nickname ?? "未登录")
                    .font(.title3.bold()).lineLimit(1)
                Text("UID \(auth.ncmProfile?.uid ?? "—")")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var avatarURL: URL? {
        let a = auth.ncmProfile?.avatar ?? ""
        return a.isEmpty ? nil : APIClient.proxiedPicURL(a, size: 160)
    }

    // MARK: 我的收藏（歌曲 / 歌单 / 歌手 三类聚合）
    @ViewBuilder
    private var myFavSection: some View {
        NavigationLink {
            SongListPage(title: "收藏歌曲", songs: player.favSongs,
                         empty: "还没有收藏歌曲\n在播放页点 ♡ 即可收藏")
        } label: {
            rowWithValue(KXLabel("收藏歌曲", icon: .heartFill),
                         value: "\(player.favSongs.count) 首")
        }
        NavigationLink {
            PlaylistListPage(title: "收藏歌单",
                             empty: "还没有收藏歌单\n在歌单页点「收藏」即可")
        } label: {
            rowWithValue(KXLabel("收藏歌单", icon: .list),
                         value: "\(auth.ncmPlaylists.filter { $0.subscribed }.count) 个")
        }
        NavigationLink {
            ArtistFavPage(onOpenArtist: { a in
                // 先关掉整个「个人中心」sheet（走 HomeView 的绑定，可靠地 dismiss sheet），
                // 再打开歌手页（RootView 全屏浮层承接）。与 SearchSheet 点歌手的范式一致。
                onClose()
                player.artistToShow = MiniArtist(id: a.id, name: a.name, cover: a.cover)
            })
            .environmentObject(player)
            .environmentObject(auth)
        } label: {
            rowWithValue(KXLabel("收藏歌手", icon: .person),
                         value: "\(player.favArtists.count) 位")
        }
    }

    // MARK: 最近播放
    @ViewBuilder
    private var recentSection: some View {
        NavigationLink {
            SongListPage(title: "最近播放", songs: player.history,
                         empty: "还没有播放记录")
        } label: {
            rowWithValue(KXLabel("最近播放", icon: .history),
                         value: "\(player.history.count) 首")
        }
    }

    // MARK: 我的歌单（新建 + 云端歌单列表）
    @ViewBuilder
    private var playlistSection: some View {
        Button {
            newPlaylistName = ""
            showCreatePlaylist = true
        } label: {
            HStack {
                KXLabel("新建网易云歌单", icon: .plusCircle)
                Spacer()
                if creating { ProgressView().scaleEffect(0.7) }
            }
        }
        .alert("新建网易云歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("取消", role: .cancel) { newPlaylistName = "" }
            Button("创建") { Task { await createPlaylist() } }
        } message: {
            Text("将在你已连接的网易云账号里真实创建一个歌单。")
        }

        if !auth.ncmBound {
            Text("绑定网易云账号后，可在这里查看和创建歌单。")
                .font(.caption).foregroundColor(.secondary)
        } else if auth.ncmPlaylists.filter({ !$0.subscribed }).isEmpty {
            Text("还没有创建过歌单，点上方「新建网易云歌单」创建第一个。")
                .font(.caption).foregroundColor(.secondary)
        } else {
            // 我的歌单段只放「我创建的」(subscribed == false)；
            // 「我收藏的歌单」(subscribed == true) 归到「我的收藏 → 收藏歌单」。
            ForEach(auth.ncmPlaylists.filter { !$0.subscribed }) { pl in
                NavigationLink {
                    PlaylistView(ref: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover))
                } label: {
                    HStack(spacing: 10) {
                        KXCover(url: APIClient.proxiedPicURL(pl.cover, size: 100))
                            .frame(width: 40, height: 40).cornerRadius(KXRadius.cover)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl.name).font(.subheadline).lineLimit(1)
                            Text("\(pl.trackCount) 首 · \(pl.creator)")
                                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(pl.trackCount)").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @MainActor
    private func createPlaylist() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty else { return }
        guard auth.ncmBound else { infoMessage = "请先扫码绑定网易云账号"; return }
        creating = true
        do {
            _ = try await APIClient.ncmCreatePlaylist(name: name)
            await auth.loadNCMPlaylists()
            infoMessage = "已在网易云创建歌单「\(name)」"
        } catch {
            infoMessage = "创建失败：\(error.localizedDescription)"
        }
        creating = false
    }

    // MARK: 网易云账号
    @ViewBuilder
    private var ncmSection: some View {
        HStack(spacing: 10) {
            KXIcon(icon: auth.ncmBound ? .checkCircle : .person,
                   size: 19, color: .kxAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.ncmBound ? (auth.ncmProfile?.nickname ?? "网易云") : "未连接网易云")
                    .font(.subheadline.bold())
                Text(auth.ncmBound ? "已登录" : "扫码登录后可收藏并管理歌单")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }

        Button { showQR = true } label: {
            KXLabel(auth.ncmBound ? "切换账号 / 重新扫码" : "扫码登录网易云", icon: .qr)
        }

        Button(role: .destructive) {
            Task {
                await auth.unbindNCM()
                infoMessage = "已退出网易云账号，收藏仅保存在本机"
            }
        } label: {
            KXLabel("退出网易云账号", icon: .unlink)
        }
    }

    // MARK: 设置
    @ViewBuilder
    private var settingsSection: some View {
        NavigationLink {
            SettingsView()
                .environmentObject(player)
                .environmentObject(auth)
        } label: {
            KXLabel("设置", icon: .gear)
        }
        rowWithValue(KXLabel("播放音质", icon: .wave),
                     value: APIClient.audioQualityName,
                     highlight: true)
    }

    // MARK: 服务状态
    @ViewBuilder
    /// 统一的「图标 + 标题 + 右侧值」行：委托给 KXListRow，与个人中心 / 设置共用同一套样式。
    private func rowWithValue(_ label: KXLabel, value: String,
                              highlight: Bool = false) -> some View {
        KXListRow(icon: label.icon, title: label.title,
                  value: value, valueHighlighted: highlight)
    }
}

// MARK: - 网易云扫码登录
struct NCMQRView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var auth: AuthStore
    @State private var pollTask: Task<Void, Never>?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("用网易云 App 扫码登录")
                    .font(.title3.bold())
                Text("请在另一台设备上打开网易云 App → 扫一扫；扫码后在手机上点「确认登录」。")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 230, height: 230)
                        .shadow(radius: 8)
                    if let img = auth.qrImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(width: 210, height: 210)
                    } else {
                        ProgressView().frame(width: 210, height: 210)
                    }
                }

                Text(auth.qrMessage)
                    .font(.subheadline)
                    .foregroundColor(auth.qrBound ? .kxAccent : .secondary)
                    .multilineTextAlignment(.center)

                if auth.qrBound {
                    HStack(spacing: 6) {
                        KXIcon(icon: .checkCircle, size: 17, color: .kxAccent)
                        Text("已连接网易云 · \(auth.ncmProfile?.nickname ?? "网易云账号")")
                            .foregroundColor(.kxAccent)
                    }
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent).tint(.kxAccent)
                } else {
                    Button {
                        startPolling(createQR: true)
                    } label: {
                        KXLabel("刷新二维码", icon: .refresh)
                    }
                    .buttonStyle(.bordered)

                    if let qr = auth.qrImage {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(qr, nil, nil, nil)
                            saved = true
                        } label: {
                            KXLabel(saved ? "已保存到相册" : "保存二维码到相册",
                                    icon: saved ? .check : .download)
                        }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                        Text("只有一台手机时：保存后打开网易云 App → 扫一扫 → 从相册选取二维码，即可完成登录；回到本页会自动显示成功。")
                            .font(.caption2).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }
                Spacer()
            }
            .padding(.top, 28)
            .navigationTitle("网易云登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { pollTask?.cancel(); dismiss() }
                }
            }
            .task { startPolling(createQR: true) }
            .onChange(of: scenePhase) { phase in
                if phase == .active, !auth.qrBound { startPolling(createQR: false) }
            }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private func startPolling(createQR: Bool) {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            if createQR { await auth.startQR() }
            while !Task.isCancelled, !auth.qrBound {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled || auth.qrBound { break }
                await auth.resumeQRCheck()
            }
        }
    }
}

// MARK: - 通用歌曲列表（收藏 / 历史）
struct SongListPage: View {
    @EnvironmentObject var player: PlayerEngine
    let title: String
    let songs: [Song]
    let empty: String

    var body: some View {
        Group {
            if songs.isEmpty {
                VStack(spacing: 14) {
                    KXIcon(icon: .list, size: 42, color: .secondary)
                    Text(empty).font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                List(Array(songs.enumerated()), id: \.element.id) { i, s in
                    Button {
                        player.playSongs(songs, index: i)
                    } label: {
                        HStack(spacing: 12) {
                            KXCover(url: APIClient.coverURL(s.cover, size: 120))
                                .frame(width: 46, height: 46).cornerRadius(KXRadius.cover)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.subheadline).lineLimit(1)
                                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if player.current?.id == s.id {
                                KXIcon(icon: .wave, size: 17, color: .kxAccent)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
    }
}

// MARK: - 收藏歌单列表（「我的收藏 → 收藏歌单」进入，仅展示已收藏的歌单）
// 两处历史坑都已修：
//  1) 列表曾在进入瞬间把歌单数组快照成静态 let，未拉完则恒空、要退出重进才显示
//     → 改为从 auth 实时计算过滤。
//  2) 点歌单曾用 NavigationLink(value:) 值驱动，而 destination 只注册在个人中心根 List 上，
//     第二层页面解析不到、跳转挂起，要 pop 回列表才补执行 → 改为闭包型 NavigationLink。
struct PlaylistListPage: View {
    @EnvironmentObject var auth: AuthStore
    let title: String
    let empty: String

    /// 直接从 auth 实时读取并过滤「我收藏的歌单」，而不是在点进页面那一刻把
    /// auth.ncmPlaylists 快照成静态数组——若当时歌单尚未拉取完，列表会一直是空，
    /// 必须退出重进才显示（用户反馈的「收藏歌单打开看不到列表」）。
    private var playlists: [NCMPlaylist] {
        auth.ncmPlaylists.filter { $0.subscribed }
    }

    var body: some View {
        Group {
            if playlists.isEmpty {
                VStack(spacing: 14) {
                    KXIcon(icon: .list, size: 42, color: .secondary)
                    Text(empty).font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                List(playlists) { pl in
                    // 闭包型 destination：点击立即 push 歌单详情。
                    // 不能用 NavigationLink(value:)：destination 只注册在个人中心根 List 上，
                    // 第二层页面触发时解析不到，跳转会挂起直到 pop 回列表才执行（闪屏/延迟）。
                    NavigationLink {
                        PlaylistView(ref: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover))
                    } label: {
                        HStack(spacing: 10) {
                            KXCover(url: APIClient.proxiedPicURL(pl.cover, size: 120))
                                .frame(width: 44, height: 44).cornerRadius(KXRadius.cover)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name).font(.subheadline).lineLimit(1)
                                Text("\(pl.trackCount) 首 · \(pl.creator)")
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(pl.trackCount)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
    }
}

// MARK: - 收藏歌手列表（「我的收藏 → 收藏歌手」进入，点选打开歌手页）
struct ArtistFavPage: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    /// 点歌手：由外部先关掉个人中心 sheet，再打开歌手页（RootView 全屏浮层承接）。
    /// 否则 sheet 未关时 fullScreenCover 会被同层挡住，要等手动退出收藏页才弹出来。
    let onOpenArtist: (MiniArtist) -> Void

    var body: some View {
        Group {
            if player.favArtists.isEmpty {
                VStack(spacing: 14) {
                    KXIcon(icon: .person, size: 42, color: .secondary)
                    Text("还没有收藏歌手\n在歌手页点 ♡ 即可收藏").font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                List(player.favArtists) { a in
                    Button {
                        onOpenArtist(a)
                    } label: {
                        HStack(spacing: 12) {
                            KXCover(url: APIClient.coverURL(a.cover, size: 120))
                                .frame(width: 44, height: 44).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name).font(.subheadline).lineLimit(1)
                                Text("已收藏歌手").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            KXIcon(icon: .heartFill, size: 16, color: .kxAccent)
                        }
                    }
                    .foregroundColor(.primary)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("收藏歌手")
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
    }
}
