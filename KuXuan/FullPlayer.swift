import SwiftUI
import UIKit

struct FullPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    @State private var angle: Double = 0
    @State private var lyricIndex: Int = -1
    @State private var showLyrics = false
    @State private var sliderValue: Double = 0
    @State private var seeking = false
    @State private var showComments = false
    @State private var showMore = false

    private var song: Song? { player.current }

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
    }
    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 34
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack(alignment: .top) {
                Color.black
                backgroundLayer(W, H)
                shadeLayer(W, H)

                // 主舞台用 maxHeight:.infinity 吃掉全部剩余空间，
                // 控件组紧贴底部安全区 —— 修掉原来末尾 Spacer 造成的约 30% 空白。
                VStack(spacing: 0) {
                    topBar
                    stage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomPanel
                }
                .foregroundColor(.white)
                .padding(.top, safeTop + 4)
                .padding(.bottom, safeBottom + 8)
                .padding(.horizontal, 20)
                .frame(width: W, height: H, alignment: .top)
            }
            .frame(width: W, height: H)
            .clipped()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if player.showQueue { QueueSheet().transition(.move(edge: .bottom)) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.showQueue)
        .sheet(isPresented: $showComments) {
            CommentSheet(songID: song?.file ?? "", songTitle: song?.title ?? "")
        }
        .sheet(isPresented: $showMore) {
            SongInfoSheet(song: song)
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if player.isPlaying { angle += 0.9 }
        }
        .onChange(of: player.currentTime) { _ in syncLyric() }
        .onChange(of: player.lyrics) { _ in
            lyricIndex = -1
            syncLyric()
        }
        .onChange(of: player.currentIndex) { _ in
            lyricIndex = -1
            syncLyric()
        }
        .onAppear { syncLyric() }
    }

    // MARK: 背景
    private func backgroundLayer(_ W: CGFloat, _ H: CGFloat) -> some View {
        AsyncImage(url: APIClient.coverURL(song?.cover)) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFill()
            } else { Color.clear }
        }
        .frame(width: W, height: H)
        .scaleEffect(1.25)
        .blur(radius: 55)
        .saturation(1.4)
        .brightness(-0.32)
        .clipped()
    }

    private func shadeLayer(_ W: CGFloat, _ H: CGFloat) -> some View {
        LinearGradient(colors: [.black.opacity(0.30), .black.opacity(0.68)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: W, height: H)
    }

    // MARK: 顶部栏
    private var topBar: some View {
        ZStack {
            HStack {
                Button { player.showFullPlayer = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
                } label: {
                    Image(systemName: showLyrics ? "music.note" : "text.quote")
                        .font(.body).foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            VStack(spacing: 3) {
                Text("正在播放").font(.caption).opacity(0.75)
                Text(song?.title ?? "—").font(.subheadline.bold()).lineLimit(1)
                if let a = song?.artist, !a.isEmpty {
                    Text(a).font(.caption2).opacity(0.6).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 52)
        }
        .frame(height: 56)
    }

    // MARK: 主舞台：封面 ↔ 歌词
    @ViewBuilder
    private var stage: some View {
        ZStack {
            if showLyrics { lyricsStage } else { coverStage }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
        }
    }

    // MARK: 圆形旋转封面
    @ViewBuilder
    private var coverStage: some View {
        let coverURL = APIClient.coverURL(song?.cover)
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.white.opacity(0.07)).frame(width: 300, height: 300)
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 4))
                    default:
                        Color.white.opacity(0.12).clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 4))
                    }
                }
                .frame(width: 266, height: 266)
                .rotationEffect(.degrees(angle))
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 286, height: 286)
            }
            .frame(maxWidth: .infinity)
            Text("轻点封面查看歌词").font(.caption2).opacity(0.45)
            Spacer(minLength: 0)
        }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.height < -90 { player.next() }
                else if v.translation.height > 90 { player.prev() }
            }
        )
    }

    // MARK: 歌词：占满整块主舞台，逐行高亮 + 自动滚到中央 + 点击跳转
    @ViewBuilder
    private var lyricsStage: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // 上下留白保证首行/末行也能滚到视觉中心
                    Spacer().frame(height: 130)
                    if player.lyrics.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note").font(.title2).opacity(0.5)
                            Text("暂无歌词").font(.subheadline).opacity(0.6)
                            Text("纯音乐，请欣赏").font(.caption).opacity(0.4)
                        }
                        .id(-1)
                    } else {
                        ForEach(Array(player.lyrics.enumerated()), id: \.offset) { i, line in
                            Text(line.text.isEmpty ? "·" : line.text)
                                .font(i == lyricIndex ? .title3.bold() : .body)
                                .foregroundColor(i == lyricIndex ? .white : .white.opacity(0.42))
                                .multilineTextAlignment(.center)
                                .scaleEffect(i == lyricIndex ? 1.04 : 1.0)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 10)
                                .id(i)
                                .onTapGesture {
                                    player.seek(to: line.time)
                                    lyricIndex = i
                                }
                        }
                    }
                    Spacer().frame(height: 130)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            .mask(LinearGradient(colors: [.clear, .black.opacity(0.85), .black, .black.opacity(0.85), .clear],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear { scrollLyric(proxy) }
            .onChange(of: lyricIndex) { _ in scrollLyric(proxy) }
            .onChange(of: showLyrics) { _ in scrollLyric(proxy) }
            .onChange(of: player.lyrics) { _ in scrollLyric(proxy) }
        }
    }

    private func scrollLyric(_ proxy: ScrollViewProxy) {
        guard showLyrics, lyricIndex >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(lyricIndex, anchor: .center)
        }
    }

    // MARK: 底部面板（进度 / 控制 / 功能）
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            progressBar
            controlRow
            functionRow
        }
    }

    // MARK: 进度条
    private var progressBar: some View {
        let total = max(player.duration, 1)
        return VStack(spacing: 2) {
            Slider(value: $sliderValue, in: 0...total, onEditingChanged: { editing in
                if editing { seeking = true }
                else { player.seek(to: sliderValue); seeking = false }
            })
            .tint(.white)
            HStack {
                Text(fmt(min(sliderValue, total))).font(.caption2).monospacedDigit()
                Spacer()
                Text(fmt(player.duration)).font(.caption2).monospacedDigit()
            }
            .foregroundColor(.white.opacity(0.65))
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .onChange(of: player.currentTime) { t in
            if !seeking { sliderValue = t }
        }
        .onChange(of: player.duration) { d in
            if !seeking { sliderValue = min(sliderValue, max(d, 1)) }
        }
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let i = Int(s)
        return "\(i / 60):\(String(format: "%02d", i % 60))"
    }

    // MARK: 控制行
    private var controlRow: some View {
        HStack(spacing: 40) {
            Button { player.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 28)).foregroundColor(.white)
            }
            Button {
                if player.isPlaying { player.pause() } else { player.play() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.black)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 28)).foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: 功能行（5 等分，全部钉在宽度内）
    private var functionRow: some View {
        let idx = min(max(player.playMode, 0), 2)
        let modeIcon = ["repeat", "repeat.1", "shuffle"][idx]
        let fav = song.map { player.isFav($0.id) } ?? false
        return HStack(spacing: 0) {
            fnButton(modeIcon, player.modeName) { player.cycleMode() }
            fnButton(fav ? "heart.fill" : "heart", "收藏") {
                if let s = song { player.toggleFav(s) }
            }
            fnButton("bubble.left.and.bubble.right", "评论") { showComments = true }
            fnButton("music.note.list", "列表") { player.showQueue = true }
            fnButton("ellipsis", "更多") { showMore = true }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func fnButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    // MARK: 歌词同步（二分查找，随 currentTime 每 0.5s 更新）
    private func syncLyric() {
        let lines = player.lyrics
        guard !lines.isEmpty else {
            if lyricIndex != -1 { lyricIndex = -1 }
            return
        }
        let t = player.currentTime
        var lo = 0, hi = lines.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { found = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        if found != lyricIndex { lyricIndex = found }
    }
}

// MARK: - 歌曲信息 / 音质（后端 resolve 接口）
struct SongInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song?
    @State private var quality: String = "检测中…"
    @State private var commentCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    infoRow("标题", song?.title ?? "—")
                    infoRow("艺术家", song?.artist ?? "—")
                    infoRow("专辑", (song?.album ?? "").isEmpty ? "—" : (song?.album ?? "—"))
                    infoRow("时长", song.map { fmtDuration($0.duration) } ?? "—")
                    infoRow("网易云 ID", song?.file ?? "—")
                } header: {
                    Text("歌曲")
                }
                Section {
                    HStack {
                        Text("音质 / 可播性").font(.footnote)
                        Spacer()
                        Text(quality).font(.caption).foregroundColor(.secondary)
                    }
                    if let c = commentCount {
                        infoRow("评论数", "\(c) 条")
                    }
                } header: {
                    Text("播放")
                } footer: {
                    Text("音质信息来自后端 /api/online/resolve；上游对 VIP 歌曲可能只返回试听片段。")
                        .font(.caption2)
                }
                Section {
                    Text("音源由 Mac 上的 server.py 转发，手机需与 Mac 处于同一 Wi-Fi。")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .navigationTitle("歌曲信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.footnote)
            Spacer()
            Text(v).font(.caption).foregroundColor(.secondary)
                .lineLimit(2).multilineTextAlignment(.trailing)
        }
    }

    private func fmtDuration(_ s: Double) -> String {
        let i = Int(max(s, 0))
        return "\(i / 60):\(String(format: "%02d", i % 60))"
    }

    private func load() async {
        guard let id = song?.file, !id.isEmpty else { quality = "未知"; return }
        do {
            let r = try await APIClient.resolve(songID: id)
            quality = r.qualityText
        } catch {
            quality = "检测失败"
        }
        if let r = try? await APIClient.comments(songID: id, limit: 1, offset: 0) {
            commentCount = r.total
        }
    }
}
