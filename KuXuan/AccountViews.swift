import SwiftUI
import UIKit

// MARK: - 个人中心（作为 sheet 呈现，自带 NavigationStack）
struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: PlayerEngine

    @State private var showAuth = false
    @State private var showQR = false
    @State private var showNickname = false
    @State private var showPassword = false
    @State private var service: ServiceStatus?
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section { profileHeader }

                Section {
                    ncmSection
                } header: {
                    Text("网易云账号")
                } footer: {
                    Text("扫码登录只用于读取你的网易云资料与歌单；本机单机版不会上传任何数据。")
                        .font(.caption2)
                }

                Section("我的音乐") { myMusicSection }

                if auth.isLoggedIn {
                    Section("账号设置") { accountSection }
                }

                Section {
                    serviceSection
                } header: {
                    Text("服务状态")
                } footer: {
                    if let req = auth.status?.requireAuth, req {
                        Text("服务端已开启强制登录（KUXUAN_REQUIRE_AUTH=1）")
                    } else {
                        Text("服务端当前为免登录模式（requireAuth=false），登录属于可选增强。")
                    }
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
            .sheet(isPresented: $showAuth) {
                AuthSheetView().environmentObject(auth)
            }
            .sheet(isPresented: $showQR) {
                NCMQRView().environmentObject(auth)
            }
            .sheet(isPresented: $showNickname) {
                NicknameSheet().environmentObject(auth)
            }
            .sheet(isPresented: $showPassword) {
                PasswordSheet().environmentObject(auth)
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
                    Image(systemName: "person.fill")
                        .font(.system(size: 26)).foregroundColor(.white)
                }
            }
            .frame(width: 62, height: 62)
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

            VStack(alignment: .leading, spacing: 5) {
                Text(auth.displayName).font(.title3.bold()).lineLimit(1)
                if auth.isLoggedIn {
                    Text("@" + (auth.user?.username ?? ""))
                        .font(.caption).foregroundColor(.secondary)
                    Text("注册 \(auth.user?.createdText ?? "—") · 最近登录 \(auth.user?.loginText ?? "—")")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("登录后可使用个人资料与账号设置")
                        .font(.caption).foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(player.favs.count) 收藏", systemImage: "heart")
                    Label("\(player.history.count) 听过", systemImage: "clock")
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if !auth.isLoggedIn {
                Button("登录") { showAuth = true }
                    .buttonStyle(.borderedProminent).tint(.kxAccent)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private var avatarURL: URL? {
        let a = auth.ncmProfile?.avatar ?? ""
        return a.isEmpty ? nil : APIClient.proxiedPicURL(a)
    }

    // MARK: 网易云
    @ViewBuilder
    private var ncmSection: some View {
        if auth.ncmBound {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已绑定 · \(auth.ncmProfile?.nickname ?? "网易云")")
                        .font(.subheadline.bold())
                    Text("UID \(auth.ncmProfile?.uid ?? "—")")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(auth.ncmPlaylists.count) 个歌单")
                    .font(.caption).foregroundColor(.secondary)
            }
            Button { showQR = true } label: {
                Label("切换 / 重新扫码", systemImage: "qrcode")
            }
            Button(role: .destructive) {
                Task {
                    await auth.unbindNCM()
                    infoMessage = "已解绑网易云账号"
                }
            } label: {
                Label("解绑网易云", systemImage: "person.badge.minus")
            }
            if !auth.ncmPlaylists.isEmpty {
                ForEach(auth.ncmPlaylists) { pl in
                    NavigationLink(value: PlaylistRef(id: pl.id, name: pl.name, cover: pl.cover)) {
                        HStack(spacing: 10) {
                            KXCover(url: APIClient.proxiedPicURL(pl.cover))
                                .frame(width: 42, height: 42).cornerRadius(7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name).font(.subheadline).lineLimit(1)
                                Text("\(pl.trackCount) 首 · \(pl.creator)")
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        } else {
            Text("绑定后可查看你的网易云头像、昵称与「我创建的歌单」。")
                .font(.caption).foregroundColor(.secondary)
            Button { showQR = true } label: {
                Label("扫码登录网易云", systemImage: "qrcode")
                    .foregroundColor(.kxAccent)
            }
        }
    }

    // MARK: 我的音乐
    @ViewBuilder
    private var myMusicSection: some View {
        NavigationLink {
            SongListPage(title: "我的收藏", songs: player.favSongs,
                         empty: "还没有收藏歌曲\n在播放页点 ♡ 即可收藏")
        } label: {
            HStack {
                Label("我的收藏", systemImage: "heart.fill")
                Spacer()
                Text("\(player.favSongs.count) 首").foregroundColor(.secondary).font(.caption)
            }
        }
        NavigationLink {
            SongListPage(title: "最近播放", songs: player.history,
                         empty: "还没有播放记录")
        } label: {
            HStack {
                Label("最近播放", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(player.history.count) 首").foregroundColor(.secondary).font(.caption)
            }
        }
    }

    // MARK: 账号设置
    @ViewBuilder
    private var accountSection: some View {
        Button { showNickname = true } label: {
            Label("修改昵称", systemImage: "pencil")
        }
        Button { showPassword = true } label: {
            Label("修改密码", systemImage: "lock.rotation")
        }
        Button(role: .destructive) {
            Task { await auth.logout(); infoMessage = "已退出登录" }
        } label: {
            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    // MARK: 服务状态
    @ViewBuilder
    private var serviceSection: some View {
        HStack {
            Label("服务器", systemImage: "server.rack")
            Spacer()
            Text(APIClient.baseURL).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        if let s = service {
            HStack {
                Label("本地曲库", systemImage: "music.note")
                Spacer()
                Text("\(s.library) 首").font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Label("上游音源", systemImage: "network")
                Spacer()
                Text(s.onlineApi).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            HStack {
                Label("局域网地址", systemImage: "wifi")
                Spacer()
                Text("\(s.ip):\(s.port)").font(.caption2).foregroundColor(.secondary)
            }
        } else {
            Text("服务状态读取失败，请确认 Mac 上 server.py 正在运行")
                .font(.caption).foregroundColor(.secondary)
        }
        if let s = auth.status {
            HStack {
                Label("账号体系", systemImage: "person.2")
                Spacer()
                Text("\(s.userCount) 个账号 · 会话 \(s.sessionDays) 天")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        if let e = auth.lastError {
            Text(e).font(.caption2).foregroundColor(.red)
        }
    }
}

// MARK: - 登录 / 注册
struct AuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @State private var isRegister = false
    @State private var username = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("账号（邮箱 / 手机号 / 3-64 位字符）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isRegister {
                        TextField("昵称（1-24 字）", text: $nickname)
                    }
                    SecureField("密码（8-128 位）", text: $password)
                } header: {
                    Text(isRegister ? "注册本机账号" : "登录本机账号")
                } footer: {
                    Text("账号只保存在这台 Mac 的 kuxuan.db 里，用于个人中心；服务端默认不强制登录。")
                        .font(.caption2)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text(isRegister ? "注册并登录" : "登录").bold()
                            Spacer()
                        }
                    }
                    .disabled(busy || username.isEmpty || password.count < 8)
                    .tint(.kxAccent)

                    if (auth.status?.allowRegister ?? true) {
                        Button(isRegister ? "已有账号？去登录" : "没有账号？注册一个") {
                            isRegister.toggle()
                            auth.lastError = nil
                        }
                        .font(.footnote)
                    }
                }

                if let e = auth.lastError {
                    Section {
                        Text(e).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { try? await auth.refresh() }
        }
    }

    private func submit() async {
        busy = true
        let ok = isRegister
            ? await auth.register(username: username, nickname: nickname, password: password)
            : await auth.login(username: username, password: password)
        busy = false
        if ok {
            await auth.refresh()
            dismiss()
        }
    }
}

// MARK: - 昵称 / 密码
struct NicknameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("新昵称", text: $text)
                } footer: {
                    Text("1-24 个字符").font(.caption2)
                }
                if let e = auth.lastError {
                    Text(e).font(.caption).foregroundColor(.red)
                }
            }
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Task {
                            if await auth.updateProfile(nickname: text) { dismiss() }
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = auth.user?.nickname ?? ""; auth.lastError = nil }
        }
    }
}

struct PasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @State private var old = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("当前密码", text: $old)
                    SecureField("新密码（8-128 位）", text: $new)
                    SecureField("确认新密码", text: $confirm)
                } footer: {
                    Text("修改成功后服务端会注销全部会话，需要重新登录。").font(.caption2)
                }
                if new != confirm, !confirm.isEmpty {
                    Text("两次输入的新密码不一致").font(.caption).foregroundColor(.red)
                }
                if let e = auth.lastError {
                    Text(e).font(.caption).foregroundColor(.red)
                }
                if done {
                    Text("密码已修改，请重新登录").font(.caption).foregroundColor(.green)
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Task {
                            let ok = await auth.changePassword(old: old, new: new)
                            if ok { done = true }
                        }
                    }
                    .disabled(old.isEmpty || new.count < 8 || new != confirm || done)
                }
            }
            .onAppear { auth.lastError = nil }
        }
    }
}

// MARK: - 网易云扫码登录
struct NCMQRView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    @State private var polling = true

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
                    .foregroundColor(auth.qrBound ? .green : .secondary)
                    .multilineTextAlignment(.center)

                if auth.qrBound {
                    Label("已绑定 \(auth.ncmProfile?.nickname ?? "网易云账号")",
                          systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent).tint(.kxAccent)
                } else {
                    Button {
                        Task { await auth.startQR() }
                    } label: {
                        Label("刷新二维码", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(.top, 28)
            .navigationTitle("网易云登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { polling = false; dismiss() }
                }
            }
            .task {
                await auth.startQR()
                while polling && !auth.qrBound {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if polling && !auth.qrBound { await auth.pollQR() }
                }
            }
            .onDisappear { polling = false }
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
                    Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.secondary)
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
                            KXCover(url: APIClient.coverURL(s.cover))
                                .frame(width: 46, height: 46).cornerRadius(8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.subheadline).lineLimit(1)
                                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if player.current?.id == s.id {
                                Image(systemName: "speaker.wave.2.fill").foregroundColor(.kxAccent)
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
    }
}
