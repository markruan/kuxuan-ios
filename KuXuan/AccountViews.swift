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

    @State private var showQR = false
    @State private var service: ServiceStatus?
    @State private var infoMessage: String?
    @State private var syncing = false
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section { profileHeader }

                Section("我的音乐") { myMusicSection }

                Section {
                    playlistSection
                } header: {
                    Text("我的歌单")
                } footer: {
                    Text("歌单保存在网易云账号里，在网易云 App 也能看到。")
                        .font(.caption2)
                }

                Section {
                    ncmSection
                } header: {
                    Text("网易云账号与同步")
                } footer: {
                    Text("点 ♡ 收藏会写入网易云「我喜欢的音乐」并回查红心列表；未绑定时仅保存在本机。")
                        .font(.caption2)
                }

                Section("设置") { settingsSection }

                Section {
                    serviceSection
                } header: {
                    Text("服务状态")
                } footer: {
                    Text("服务已部署在云端，手机使用移动网络或 Wi-Fi 均可访问。")
                        .font(.caption2)
                }
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
            .navigationDestination(for: PlaylistRef.self) { ref in
                PlaylistView(ref: ref)
            }
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
        service = try? await APIClient.serviceStatus()
        if auth.ncmBound { await player.syncFavsFromCloud() }
    }

    // MARK: 资料卡
    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.kx)
                if let img = avatarURL {
                    AsyncImage(url: img) { phase in
                        if case .success(let im) = phase {
                            im.resizable().scaledToFill().clipShape(Circle())
                        }
                    }
                } else {
                    KXIcon(icon: .person, size: 30, color: .white)
                }
            }
            .frame(width: 62, height: 62)
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

            VStack(alignment: .leading, spacing: 6) {
                Text(auth.ncmProfile?.nickname ?? "未绑定网易云")
                    .font(.title3.bold()).lineLimit(1)
                Text("UID \(auth.ncmProfile?.uid ?? "—")")
                    .font(.caption2).foregroundColor(.secondary)
                statusBadge
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        Text(auth.ncmBound ? "收藏同步已开启" : "未绑定 · 收藏仅存本机")
            .font(.caption2)
            .foregroundColor(.kxAccent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.kxAccent.opacity(0.12), in: Capsule())
    }

    private var avatarURL: URL? {
        let a = auth.ncmProfile?.avatar ?? ""
        return a.isEmpty ? nil : APIClient.proxiedPicURL(a)
    }

    // MARK: 我的音乐
    @ViewBuilder
    private var myMusicSection: some View {
        NavigationLink {
            SongListPage(title: "我的收藏", songs: player.favSongs,
                         empty: "还没有收藏歌曲\n在播放页点 ♡ 即可收藏")
        } label: {
            rowWithValue(KXLabel("我的收藏", icon: .heartFill),
                         value: "\(player.favSongs.count) 首")
        }
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
            Text("将在你已绑定的网易云账号里真实创建一个歌单。")
        }

        if !auth.ncmBound {
            Text("绑定网易云账号后，可在这里查看和创建歌单。")
                .font(.caption).foregroundColor(.secondary)
        } else if auth.ncmPlaylists.isEmpty {
            Text("还没有创建过歌单，点上方「新建网易云歌单」创建第一个。")
                .font(.caption).foregroundColor(.secondary)
        } else {
            ForEach(auth.ncmPlaylists) { pl in
                NavigationLink(value: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover)) {
                    HStack(spacing: 10) {
                        KXCover(url: APIClient.proxiedPicURL(pl.cover))
                            .frame(width: 40, height: 40).cornerRadius(KXRadius.cover)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(pl.name).font(.subheadline).lineLimit(1)
                                if pl.subscribed {
                                    Text("收藏")
                                        .font(.caption2).foregroundColor(.kxAccent)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.kxAccent.opacity(0.12)))
                                }
                            }
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

    // MARK: 网易云账号与同步
    @ViewBuilder
    private var ncmSection: some View {
        HStack(spacing: 10) {
            KXIcon(icon: auth.ncmBound ? .checkCircle : .person,
                   size: 19, color: .kxAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.ncmBound ? "已绑定 · \(auth.ncmProfile?.nickname ?? "网易云")" : "尚未绑定")
                    .font(.subheadline.bold())
                Text(auth.ncmBound ? "收藏、歌单与云端保持同步" : "扫码后可同步收藏并管理歌单")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }

        Button { showQR = true } label: {
            KXLabel(auth.ncmBound ? "切换账号 / 重新扫码" : "扫码绑定网易云", icon: .qr)
        }

        rowWithValue(KXLabel("收藏同步", icon: .sync), value: cloudFavText,
                     highlight: auth.ncmBound)

        Button {
            Task { await refreshCloudFavs() }
        } label: {
            HStack {
                KXLabel("立即核对云端红心", icon: .refresh)
                Spacer()
                if syncing { ProgressView().scaleEffect(0.7) }
            }
        }

        Button(role: .destructive) {
            Task {
                await auth.unbindNCM()
                infoMessage = "已解绑网易云账号，收藏将仅保存在本机"
            }
        } label: {
            KXLabel("解绑网易云", icon: .unlink)
        }
    }

    @MainActor
    private func refreshCloudFavs() async {
        guard auth.ncmBound else {
            infoMessage = "请先扫码绑定网易云账号，才能读取云端红心"
            return
        }
        syncing = true
        await player.syncFavsFromCloud()
        syncing = false
        if let n = player.cloudFavCount {
            infoMessage = "已从网易云读取 \(n) 首红心歌曲，并合并到「我的收藏」"
        } else {
            infoMessage = "云端红心读取失败，本地收藏保持不变：\(player.favSyncError ?? "未知原因")"
        }
    }

    private var cloudFavText: String {
        guard auth.ncmBound else { return "仅本机" }
        if let n = player.cloudFavCount { return "云端红心 \(n) 首" }
        return "待核对"
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
    private var serviceSection: some View {
        if let s = service {
            rowWithValue(KXLabel("本地曲库", icon: .note), value: "\(s.library) 首")
            rowWithValue(KXLabel("上游音源", icon: .network), value: s.onlineApi)
        } else {
            Text("服务状态读取失败，请确认后端服务正在运行")
                .font(.caption).foregroundColor(.secondary)
        }
        if let e = auth.lastError {
            Text(e).font(.caption2).foregroundColor(.secondary)
        }
    }

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
                        Text("已绑定 \(auth.ncmProfile?.nickname ?? "网易云账号")")
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
