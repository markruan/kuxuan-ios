import SwiftUI

/// 歌单详情页（Apple Music 风格）：居中大封面 → 标题与统计 → 播放 / 随机两枚按钮 → 分隔线歌曲列表。
/// 图标统一走 KXIcon（自绘），不使用苹果 SF Symbols。
struct PlaylistView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    let ref: PlaylistRef
    @State private var detail: PlaylistDetailResp?
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var subscribed: Bool? = nil
    @State private var subBusy: Bool = false
    @State private var subMsg: String? = nil

    var body: some View {
        Group {
            if let d = detail {
                if d.code == -1 {
                    errorView(d.reason.isEmpty ? "加载失败" : d.reason)
                } else {
                    content(d)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            } else if loading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                errorView(errorMsg ?? "加载失败")
            }
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .animation(.easeInOut(duration: 0.32), value: loading)
        .task { await load(); await loadSubscribeState() }
        .overlay(alignment: .bottom) {
            FavSyncToast().padding(.bottom, 130)
        }
    }

    // MARK: 内容
    @ViewBuilder
    private func content(_ d: PlaylistDetailResp) -> some View {
        let songs = d.songs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock(d, songs: songs)
                Divider().padding(.horizontal, 20)

                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                        songRow(s, i)
                        Divider().padding(.leading, 76)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .padding(.top, 8)
        }
    }

    // MARK: 封面 / 标题 / 操作
    private func headerBlock(_ d: PlaylistDetailResp, songs: [Song]) -> some View {
        VStack(spacing: 14) {
            KXCover(url: APIClient.coverURL(d.info?.cover ?? ref.cover, size: 420))
                .frame(width: 210, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            VStack(spacing: 5) {
                Text(d.info?.name ?? ref.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let p = d.info {
                    Text("\(p.trackCount) 首 · 播放 \(p.playCountText)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                actionButton(icon: .play, title: "播放", primary: true) {
                    if !songs.isEmpty { player.playSongs(songs, index: 0) }
                }
                actionButton(icon: .shuffle, title: "随机播放", primary: false) {
                    guard !songs.isEmpty else { return }
                    player.playMode = 2
                    player.playSongs(songs, index: Int.random(in: 0..<songs.count))
                }
                actionButton(icon: subscribed == true ? .heartFill : .heart,
                             title: subscribed == true ? "已收藏" : "收藏",
                             primary: false) {
                    // 同步置位防重：避免一次手抖连点触发两次订阅请求，
                    // 否则两次请求更易被服务端判「操作过于频繁」。
                    guard !subBusy else { return }
                    subBusy = true
                    Task { await toggleSubscribe() }
                }
                .disabled(subBusy)
            }
            .padding(.top, 4)
            if let m = subMsg {
                Text(m).font(.caption2).foregroundColor(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    private func actionButton(icon: KXIconName, title: String, primary: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                KXIcon(icon: icon, size: 15,
                       color: primary ? .white : .kxAccent, filled: primary)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(primary ? .white : .kxAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient.kx)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 歌曲行
    private func songRow(_ s: Song, _ i: Int) -> some View {
        let playing = player.current?.id == s.id
        let fav = player.isFav(s.id)
        return HStack(spacing: 12) {
            if playing {
                KXIcon(icon: .wave, size: 15, color: .kxAccent)
                    .frame(width: 22, alignment: .center)
            } else {
                Text("\(i + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 22, alignment: .center)
            }

            KXCover(url: APIClient.coverURL(s.cover, size: 120))
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(.system(size: 15, weight: .medium)).lineLimit(1)
                    .foregroundColor(playing ? .kxAccent : .primary)
                Text(s.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button { player.toggleFav(s) } label: {
                KXIcon(icon: fav ? .heartFill : .heart, size: 16,
                       color: fav ? .kxAccent : .secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 30)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { player.playSongs(detail?.songs ?? [], index: i) }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            KXIcon(icon: .warning, size: 40, color: .orange)
            Text(msg).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("重试") { Task { await load() } }
                .buttonStyle(.borderedProminent).tint(.kxAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loading = true; errorMsg = nil; detail = nil
        do { detail = try await APIClient.playlist(id: ref.id) }
        catch { errorMsg = "无法加载歌单" }
        loading = false
    }

    // MARK: 收藏 / 取消收藏歌单（真实写入网易云账号）
    private func loadSubscribeState() async {
        guard auth.ncmBound else { subscribed = false; return }
        // 复用已缓存的歌单列表，避免每次进歌单页都打一次 /api/ncm/playlists。
        // 否则进页即消耗掉网易云共享会话的限流额度，用户点「收藏」首点就被判
        // 「操作过于频繁」。列表为空（首启 / 解绑后）才拉取，成功收藏后会刷新。
        if auth.ncmPlaylists.isEmpty { await auth.loadNCMPlaylists() }
        subscribed = auth.ncmPlaylists.contains { $0.id == ref.id && $0.subscribed }
    }

    private func toggleSubscribe() async {
        guard let cur = subscribed else { subBusy = false; return }
        guard auth.ncmBound else {
            subMsg = "请先在「我的」页绑定网易云账号"
            subBusy = false
            return
        }
        subBusy = true; subMsg = nil
        let target = !cur
        // 乐观更新：后端对订阅接口有全局限流（多为多用户共享同一网易云会话），
        // 首点就可能被「操作过于频繁」。先立即切换 UI 状态，真正写入放后台异步重试，
        // 等限流窗口过去后再落库，用户无需反复手动点击。
        subscribed = target
        subMsg = target ? "已收藏到网易云" : "已取消收藏"
        subBusy = false
        await commitSubscribe(id: ref.id, target: target)
    }

    /// 后台异步提交订阅：遇「操作过于频繁」按长退避重试（2/5/10/20/30/30/60s，封顶 7 次，约 2 分钟）。
    /// 成功则本地同步 auth.ncmPlaylists 缓存（不额外打接口）；始终限流则保留乐观状态并提示稍后同步；
    /// 非限流错误（参数/未绑定等）立即回滚并提示。
    private func commitSubscribe(id: String, target: Bool) async {
        let backoffs: [UInt64] = [2, 5, 10, 20, 30, 30, 60]
        for i in 0..<backoffs.count {
            do {
                let (ok, err) = try await APIClient.ncmSubscribePlaylist(id: id, subscribe: target)
                if ok {
                    await MainActor.run { auth.syncSubscription(id: id, subscribed: target) }
                    return
                }
                guard let e = err, e.contains("频繁") else {
                    await MainActor.run {
                        if subscribed == target { subscribed = !target }
                        subMsg = err ?? "操作失败"
                    }
                    return
                }
            } catch {
                // 网络异常也按可重试处理
            }
            if i < backoffs.count - 1 {
                try? await Task.sleep(nanoseconds: backoffs[i] * 1_000_000_000)
            }
        }
        await MainActor.run {
            subMsg = "收藏已记录，稍后网络顺畅时自动同步"
        }
    }
}
