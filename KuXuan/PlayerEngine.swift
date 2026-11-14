import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI

/// 播放引擎：包装 AVPlayer，负责播放控制、后台/锁屏、主色提取、歌词、收藏与历史。
/// 不标记 @MainActor：App 初始化时创建实例会触发「main-actor 隔离」编译错误。
/// 所有 UI 更新都显式切回主线程（MainActor.run）。
final class PlayerEngine: ObservableObject {

    @Published var queue: [Song] = []
    @Published var currentIndex: Int = -1
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    /// 实时播放时间：直接读 AVPlayer，精度到帧。
    /// 区别于 @Published currentTime（由 0.5s 周期观察器采样）——全屏歌词逐字/逐句进度若读 currentTime，
    /// 会最多滞后 0.5s，表现为「歌词进度和歌曲不一致」。歌词视图的 onReceive 应读此值。
    var playbackTime: Double {
        let t = player.currentTime()
        return t.isValid ? t.seconds : currentTime
    }
    @Published var duration: Double = 0
    @Published var playMode: Int = 0          // 0 列表循环 / 1 单曲循环 / 2 随机
    @Published var showFullPlayer: Bool = false
    @Published var showQueue: Bool = false
    @Published var coverColor: UIColor = UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1)
    @Published var lyrics: [LyricLine] = []
    @Published var favs: Set<String> = []
    @Published var favSongs: [Song] = []      // 完整歌曲对象，供「我的收藏」列表展示/播放
    /// 「未与云端确认」的本地收藏 id：本地曲库、未绑定网易云期间的收藏。
    /// 云端同步时必须保留，否则会被误判成「云端已取消」而丢掉。持久化避免重启后丢失。
    private var localOnlyFavIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "kuxuan_local_only_favs") ?? [])
    /// 每次 playCurrent 递增；歌词/封面异步请求回写前校验，杜绝旧请求晚到覆盖新歌。
    private var mediaRequestID: UInt64 = 0
    /// 连点收藏时的请求序号：同一首歌/同一个歌手只认最后一次点击的云端结果，
    /// 否则先发出的请求晚到会回滚掉用户最新的意图（并让红心状态与云端不一致）。
    private var favSeq: UInt64 = 0
    private var latestFavSeq: [String: UInt64] = [:]
    private var favArtistSeq: UInt64 = 0
    private var latestFavArtistSeq: [String: UInt64] = [:]
    @Published var history: [Song] = []
    /// 待打开的歌手页（任意位置点歌手名/头像都会设置它，由 RootView 的 fullScreenCover 承接）
    @Published var artistToShow: MiniArtist?
    /// 收藏（关注）的歌手，与网易云「关注」同步；本地缓存保证离线也能展示
    @Published var favArtists: [MiniArtist] = []
    private var favArtistSet: Set<String> = []
    /// 收藏歌手的短提示（成功 / 未连接 / 失败回滚）
    @Published var favArtistNotice: String?
    /// 收藏云同步的短提示（成功 / 未绑定 / 失败回滚），由 UI 以浮层展示，约 2.8s 自动消失
    @Published var favNotice: String?
    /// 网易云账号里真实存在的红心数量（nil = 尚未成功读取过）
    @Published var cloudFavCount: Int?
    /// 收藏云端同步是否已结束（成功或失败都算）。首次同步完成前，空收藏列表显示骨架而不是空态文案。
    @Published var cloudSyncDone = false
    /// 云端红心读取失败原因，仅用于个人中心提示，不影响本地收藏
    @Published var favSyncError: String?
    /// 播放失败提示（版权/网络受限/上游返回非音频），约 2.8s 自动消失
    @Published var playError: String?
    /// 已为哪首歌处理过「播放失败→跳过」，避免 KVO 与通知重复触发连跳
    private var failureHandledFor: String?
    private var failObserver: NSObjectProtocol?
    private var itemStatusToken: NSKeyValueObservation?

    private let player = AVPlayer()
    private var timeToken: Any?
    private var endObserver: NSObjectProtocol?
    private var currentCoverImage: UIImage?

    var current: Song? {
        currentIndex >= 0 && currentIndex < queue.count ? queue[currentIndex] : nil
    }
    var modeName: String { ["列表循环", "单曲循环", "随机播放"][playMode] }

    // MARK: - 生命周期
    init() {
        loadFavs(); loadFavSongs(); loadHistory(); loadFavArtists()
        let iv = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeToken = player.addPeriodicTimeObserver(forInterval: iv, queue: .main) { [weak self] t in
            guard let s = self else { return }
            s.currentTime = t.seconds
            if let d = s.player.currentItem?.duration.seconds, d.isFinite, d > 0 { s.duration = d }
            if s.duration > 0 { s.updateNowPlayingProgress() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            self?.next(auto: true)
        }
        // 播放失败（版权/网络受限/上游返回非音频 451）：不要「直接停止」卡死，
        // 给出提示并自动跳过下一首（只有一首时仅提示并暂停）。
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            self?.handlePlaybackFailure()
        }
    }

    func setup() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default,
                              options: [.allowBluetooth, .defaultToSpeaker])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { }
        setupRemote()
        setupSessionObservers()
    }

    // 后台/锁屏保活：系统音频被打断或路由变化后，自动恢复会话并续播
    private func setupSessionObservers() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.ended.rawValue {
                try? AVAudioSession.sharedInstance().setActive(true)
                if self.isPlaying { self.player.play() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            // 输出设备断开（如拔出耳机）：暂停，避免无声续播
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self.player.pause(); self.isPlaying = false
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            // 局域网流缓冲卡顿：立即重试续播
            self.player.play()
        }
    }

    // MARK: - 播放控制
    func playSongs(_ songs: [Song], index: Int) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(index, 0), songs.count - 1)
        playCurrent(openFull: true)
    }

    func playCurrent(openFull: Bool = true) {
        guard let s = current, let url = APIClient.streamURL(s.file) else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        // 监听当前曲目的加载状态：若上游返回非音频（如 451 JSON），
        // AVPlayer 会置为 .failed，这里据此触发「失败→跳过」，避免界面卡在假播放。
        failureHandledFor = nil
        itemStatusToken?.invalidate()
        itemStatusToken = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard let self else { return }
            if observed.status == .failed {
                self.handlePlaybackFailure()
            }
        }
        player.play()
        isPlaying = true
        duration = s.duration
        currentTime = 0
        // 只在「显式点歌」时打开全屏页；切歌（next/prev）保持当前页状态，
        // 绝不因为切歌把正在看的全屏播放页关掉。
        if openFull { showFullPlayer = true }
        addHistory(s)
        mediaRequestID += 1
        let requestID = mediaRequestID
        Task { await loadLyric(s.file, requestID: requestID) }
        Task { await updateCover(s.cover, requestID: requestID) }
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
        updateNowPlayingRate()
    }
    func play() { player.play(); isPlaying = true; updateNowPlayingRate() }
    func pause() { player.pause(); isPlaying = false; updateNowPlayingRate() }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        let i = currentIndex
        switch playMode {
        case 1:
            if auto { player.seek(to: .zero); player.play(); isPlaying = true; return }
            fallthrough
        case 2:
            if queue.count == 1 { player.seek(to: .zero); player.play(); isPlaying = true; return }
            var r = i
            while r == i { r = Int.random(in: 0..<queue.count) }
            currentIndex = r; playCurrent(openFull: false); return
        default:
            currentIndex = (i < queue.count - 1) ? i + 1 : 0
            playCurrent(openFull: false); return
        }
    }

    func prev() {
        if player.currentTime().seconds > 3 { player.seek(to: .zero); return }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        playCurrent(openFull: false)
    }

    // 上下滑切歌：无论进度，直接上一首/下一首
    func prevSong() {
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        playCurrent(openFull: false)
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    func cycleMode() { playMode = (playMode + 1) % 3 }

    // MARK: - 收藏（云端真实写入）
    func toggleFav(_ song: Song) {
        let willFav = !favs.contains(song.id)
        applyFav(song, liked: willFav)          // 先乐观更新本地，点击立刻有反馈
        favSeq += 1
        let seq = favSeq
        latestFavSeq[song.id] = seq

        // 关键修复：在线歌曲 id 是 "online:<数字>"（后端 _norm_song 统一加前缀），
        // 必须剥掉前缀才能拿到真实网易云 id。此前直接判断 song.id 是否纯数字，
        // 结果所有在线歌曲都被挡在云同步之外、只写本机 —— 用户说的「假收藏」。
        // 只有本地曲库（id 非数字）才确实无法对应云端歌曲，仅存本机。
        guard let ncmID = song.ncmID else {
            markLocalOnly(song.id)     // 本地曲库不与云端对应，同步时必须保留
            showFavNotice("本地曲目仅保存在本机")
            return
        }
        Task {
            do {
                _ = try await APIClient.ncmLike(songID: ncmID, like: willFav)
                await MainActor.run {
                    guard latestFavSeq[song.id] == seq else { return }
                    latestFavSeq.removeValue(forKey: song.id)
                    // 后端 /ncm/like 的 verified=false 只表示 /likelist 缓存未刷新，写入本身已成功，
                    // 绝不能据此回滚本地收藏；成功也不弹提示，红心状态变化本身就是反馈。
                    unmarkLocalOnly(song.id)
                    if let n = cloudFavCount {
                        cloudFavCount = max(0, n + (willFav ? 1 : -1))
                    }
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    guard latestFavSeq[song.id] == seq else { return }
                    latestFavSeq.removeValue(forKey: song.id)
                    if msg.contains("尚未绑定") || msg.contains("NOT_BOUND") {
                        // 未绑定期间的在线收藏同样要保留，否则下次云端同步会被当成「云端已删」丢掉
                        markLocalOnly(song.id)
                        showFavNotice("仅保存在本机")
                    } else {
                        unmarkLocalOnly(song.id)
                        // 远端明确失败：回滚本地，避免两端状态长期不一致。
                        // 只有本地状态仍是本次点击的期望值时才回滚，避免覆盖用户后续点击。
                        if favs.contains(song.id) == willFav {
                            applyFav(song, liked: !willFav)
                        }
                        showFavNotice("同步失败，已还原：\(msg)")
                    }
                }
            }
        }
    }

    /// 从网易云拉取真实红心列表，合并进「我的收藏」，让列表反映云端而不是只反映本机。
    /// 策略是只增不减：云端有的补齐，本地独有的（本地曲库、未绑定期间的收藏）保留。
    /// 任何网络/解析失败都不改动本地数据，避免把用户收藏清空。
    func syncFavsFromCloud() async {
        // 无论成功还是失败都结束骨架态，网络异常时不会把用户永远卡在占位上。
        defer { Task { @MainActor in self.cloudSyncDone = true } }
        do {
            let resp = try await APIClient.ncmLikeList()
            await MainActor.run {
                cloudFavCount = resp.count
                favSyncError = nil
                // 云端有红心但详情补全失败时，不能拿空列表覆盖本地
                if resp.count > 0 && resp.songs.isEmpty {
                    favSyncError = "云端返回 \(resp.count) 首红心，但歌曲详情拉取失败"
                    return
                }
                var merged = resp.songs
                let cloudIDs = Set(resp.songs.map { $0.id })
                // 保留本地独有的两类：本地曲库（无 ncmID）与「未绑定/未确认期间」的收藏。
                // 早期只保留 s.ncmID == nil，会把未绑定期间收藏的在线歌曲误当「云端已删」丢掉。
                for s in favSongs where !cloudIDs.contains(s.id) &&
                    (s.ncmID == nil || localOnlyFavIDs.contains(s.id)) {
                    merged.append(s)
                }
                favSongs = merged
                favs = Set(merged.map { $0.id })
                saveFavs()
                saveFavSongs()
            }
        } catch {
            await MainActor.run { favSyncError = error.localizedDescription }
        }
    }

    private func markLocalOnly(_ id: String) {
        localOnlyFavIDs.insert(id)
        UserDefaults.standard.set(Array(localOnlyFavIDs), forKey: "kuxuan_local_only_favs")
    }
    private func unmarkLocalOnly(_ id: String) {
        guard localOnlyFavIDs.remove(id) != nil else { return }
        UserDefaults.standard.set(Array(localOnlyFavIDs), forKey: "kuxuan_local_only_favs")
    }

    private func applyFav(_ song: Song, liked: Bool) {
        if liked {
            guard !favs.contains(song.id) else { return }
            favs.insert(song.id)
            favSongs.insert(song, at: 0)
        } else {
            guard favs.contains(song.id) else { return }
            favs.remove(song.id)
            favSongs.removeAll { $0.id == song.id }
            unmarkLocalOnly(song.id)
        }
        saveFavs()
        saveFavSongs()
    }

    private func showFavNotice(_ text: String) {
        Task { @MainActor in
            favNotice = text
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if favNotice == text { favNotice = nil }
        }
    }

    func isFav(_ id: String) -> Bool { favs.contains(id) }

    // MARK: - 收藏歌手（同步网易云关注）
    func isFavArtist(_ id: String) -> Bool { favArtistSet.contains(id) }

    /// 收藏 / 取消收藏歌手：真实写入网易云「关注」。乐观更新本地，再回写云端；
    /// 失败则回滚并提示（未连接网易云时明确引导去个人中心连接）。
    func toggleFavArtist(_ artist: MiniArtist) {
        let willFav = !isFavArtist(artist.id)
        applyFavArtist(artist, fav: willFav)
        favArtistSeq += 1
        let seq = favArtistSeq
        latestFavArtistSeq[artist.id] = seq
        Task {
            do {
                if willFav {
                    _ = try await APIClient.artistSub(id: artist.id)
                } else {
                    _ = try await APIClient.artistUnsub(id: artist.id)
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    // 连点时只处理最后一次：旧请求失败不能回滚掉用户新的收藏状态
                    guard latestFavArtistSeq[artist.id] == seq else { return }
                    latestFavArtistSeq.removeValue(forKey: artist.id)
                    if isFavArtist(artist.id) == willFav {
                        applyFavArtist(artist, fav: !willFav)
                    }
                    if msg.contains("尚未绑定") || msg.contains("NOT_BOUND") {
                        showFavArtistNotice("请先在个人中心连接网易云")
                    } else {
                        showFavArtistNotice("操作失败：\(msg)")
                    }
                }
            }
        }
    }

    /// 从网易云拉取真实关注列表，合并进本地收藏歌手（只增不减，避免覆盖本地缓存）。
    func syncFavArtistsFromCloud() async {
        defer { Task { @MainActor in self.cloudSyncDone = true } }
        do {
            let list = try await APIClient.artistSublist()
            await MainActor.run {
                for a in list where !favArtistSet.contains(a.id) {
                    favArtists.append(a); favArtistSet.insert(a.id)
                }
                saveFavArtists()
            }
        } catch {
            // 网络/解析失败不改动本地数据，保持上次成功的缓存
        }
    }

    private func applyFavArtist(_ artist: MiniArtist, fav: Bool) {
        if fav {
            guard !favArtistSet.contains(artist.id) else { return }
            favArtists.insert(artist, at: 0); favArtistSet.insert(artist.id)
        } else {
            guard favArtistSet.contains(artist.id) else { return }
            favArtists.removeAll { $0.id == artist.id }; favArtistSet.remove(artist.id)
        }
        saveFavArtists()
    }

    private func showFavArtistNotice(_ text: String) {
        Task { @MainActor in
            favArtistNotice = text
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if favArtistNotice == text { favArtistNotice = nil }
        }
    }

    private func loadFavArtists() {
        guard let d = UserDefaults.standard.data(forKey: "kuxuan_fav_artists"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        let list = arr.map { MiniArtist(dict: $0) }
        favArtists = list; favArtistSet = Set(list.map { $0.id })
    }
    private func saveFavArtists() {
        let arr = favArtists.map { ["id": $0.id, "name": $0.name, "cover": $0.cover] }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(d, forKey: "kuxuan_fav_artists")
        }
    }

    // MARK: - 播放失败兜底
    /// 当前曲目无法播放（版权/网络受限/上游 451）时调用：
    /// 只有一首就暂停并提示；多首则提示后自动切下一首，避免「直接停止」卡死。
    private func handlePlaybackFailure() {
        guard let failed = current, isPlaying else { return }
        // 同步置位去重：KVO 与 failedToPlayToEndTime 通知可能都触发，避免连跳两首
        guard failureHandledFor != failed.id else { return }
        failureHandledFor = failed.id
        let fid = failed.id
        let title = failed.title
        Task { @MainActor in
            // 切歌后 current 已改变，则本次失败事件属于旧曲目，忽略
            guard self.current?.id == fid else { return }
            if self.queue.count <= 1 {
                self.player.pause()
                self.isPlaying = false
                self.showPlayError("「\(title)」无法播放（版权或网络受限）")
            } else {
                self.showPlayError("「\(title)」无法播放，已切换下一首")
                self.next(auto: true)
            }
        }
    }

    private func showPlayError(_ text: String) {
        Task { @MainActor in
            playError = text
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if playError == text { playError = nil }
        }
    }

    private func saveFavSongs() {
        let arr = favSongs.map { $0.toDict() }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(d, forKey: "kuxuan_fav_songs")
        }
    }
    private func loadFavSongs() {
        guard let d = UserDefaults.standard.data(forKey: "kuxuan_fav_songs"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        favSongs = arr.map { Song(dict: $0) }
    }

    // MARK: - 主色 / 歌词
    private func updateCover(_ path: String, requestID: UInt64) async {
        guard let img = await APIClient.fetchImage(path) else { return }
        let c = dominantColor(img)
        await MainActor.run {
            // 切歌竞态：旧歌封面/主色请求可能晚于新歌返回，序号不符就丢弃
            guard requestID == self.mediaRequestID else { return }
            self.currentCoverImage = img
            withAnimation(.easeInOut(duration: 0.6)) { self.coverColor = c }
            self.updateNowPlaying()
        }
    }

    func loadLyric(_ file: String, requestID: UInt64) async {
        guard !file.isEmpty else {
            await MainActor.run {
                guard requestID == self.mediaRequestID else { return }
                lyrics = []
            }
            return
        }
        do {
            let d = try await APIClient.lyricJSON(file: file)
            let lrc = (d["lrc"] as? String) ?? ""
            let yrc = (d["yrc"] as? String) ?? ""
            let tlyric = (d["tlyric"] as? String) ?? ""
            let lines = parseEnhancedLyrics(lrc: lrc, yrc: yrc, tlyric: tlyric)
            await MainActor.run {
                guard requestID == self.mediaRequestID else { return }
                lyrics = lines
            }
        } catch {
            // 回退：旧纯文本接口
            do {
                let text = try await APIClient.lyric(file: file)
                let lines = parseLRC(text)
                await MainActor.run {
                    guard requestID == self.mediaRequestID else { return }
                    lyrics = lines
                }
            } catch {
                await MainActor.run {
                    guard requestID == self.mediaRequestID else { return }
                    lyrics = []
                }
            }
        }
    }

    // MARK: - 收藏 / 历史 持久化
    private func addHistory(_ s: Song) {
        var h = history.filter { $0.id != s.id }
        h.insert(s, at: 0)
        history = Array(h.prefix(50))
        saveHistory()
    }
    private func saveHistory() {
        let arr = history.map { $0.toDict() }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(d, forKey: "kuxuan_history")
        }
    }
    private func loadHistory() {
        guard let d = UserDefaults.standard.data(forKey: "kuxuan_history"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        history = arr.map { Song(dict: $0) }
    }
    private func saveFavs() {
        UserDefaults.standard.set(Array(favs), forKey: "kuxuan_favs")
    }
    private func loadFavs() {
        favs = Set(UserDefaults.standard.array(forKey: "kuxuan_favs") as? [String] ?? [])
    }

    // MARK: - 锁屏 / 控制中心
    private func setupRemote() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.play() }; return .success }
        rc.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.pause() }; return .success }
        rc.nextTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.next() }; return .success }
        rc.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.prev() }; return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.toggle() }; return .success }
    }

    private func updateNowPlaying() {
        guard let s = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyAlbumTitle: s.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = currentCoverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func updateNowPlayingProgress() {
        let c = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        var copy = c
        copy[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        copy[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = copy
    }
    private func updateNowPlayingRate() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        updateNowPlayingProgress()
    }
}

extension Song {
    func toDict() -> [String: Any] {
        ["id": id, "file": file, "title": title, "artist": artist, "artistId": artistId,
         "album": album, "duration": duration, "hasLyric": hasLyric, "cover": cover,
         "picUrl": picUrl, "online": online]
    }
}
