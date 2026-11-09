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
    @Published var duration: Double = 0
    @Published var playMode: Int = 0          // 0 列表循环 / 1 单曲循环 / 2 随机
    @Published var showFullPlayer: Bool = false
    @Published var showQueue: Bool = false
    @Published var coverColor: UIColor = UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1)
    @Published var lyrics: [LyricLine] = []
    @Published var favs: Set<String> = []
    @Published var history: [Song] = []

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
        loadFavs(); loadHistory()
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
    }

    func setup() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
        setupRemote()
    }

    // MARK: - 播放控制
    func playSongs(_ songs: [Song], index: Int) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(index, 0), songs.count - 1)
        playCurrent()
    }

    func playCurrent() {
        guard let s = current, let url = APIClient.streamURL(s.file) else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        duration = s.duration
        currentTime = 0
        showFullPlayer = true
        addHistory(s)
        Task { await loadLyric(s.file) }
        Task { await updateCover(s.cover) }
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
            currentIndex = r; playCurrent(); return
        default:
            currentIndex = (i < queue.count - 1) ? i + 1 : 0
            playCurrent(); return
        }
    }

    func prev() {
        if player.currentTime().seconds > 3 { player.seek(to: .zero); return }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        playCurrent()
    }

    // 上下滑切歌：无论进度，直接上一首/下一首
    func prevSong() {
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        playCurrent()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    func cycleMode() { playMode = (playMode + 1) % 3 }

    func toggleFav(_ song: Song) {
        if favs.contains(song.id) { favs.remove(song.id) } else { favs.insert(song.id) }
        saveFavs()
    }
    func isFav(_ id: String) -> Bool { favs.contains(id) }

    // MARK: - 主色 / 歌词
    private func updateCover(_ path: String) async {
        guard let img = await APIClient.fetchImage(path) else { return }
        let c = dominantColor(img)
        await MainActor.run {
            self.currentCoverImage = img
            withAnimation(.easeInOut(duration: 0.6)) { self.coverColor = c }
            self.updateNowPlaying()
        }
    }

    func loadLyric(_ file: String) async {
        guard !file.isEmpty else { await MainActor.run { lyrics = [] }; return }
        do {
            let text = try await APIClient.lyric(file: file)
            let lines = parseLRC(text)
            await MainActor.run { lyrics = lines }
        } catch {
            await MainActor.run { lyrics = [] }
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
        ["id": id, "file": file, "title": title, "artist": artist, "album": album,
         "duration": duration, "hasLyric": hasLyric, "cover": cover, "picUrl": picUrl, "online": online]
    }
}
