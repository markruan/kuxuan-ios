import SwiftUI

struct FullPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    @State private var angle: Double = 0
    @State private var lyricIndex: Int = -1
    @State private var showMore = false
    @State private var sliderValue: Double = 0
    @State private var seeking = false

    private var song: Song? { player.current }

    var body: some View {
        // 关键：用 GeometryReader 拿到真实屏幕尺寸，把每一层都钉死在这个宽度内。
        // 背景 AsyncImage 的 scaledToFill 若不加 frame，会按原图像素撑大 ZStack
        // （实测撑到约 921pt，屏幕仅 393pt），导致前景坐标系整体右移、
        // 最左的返回键与最左/最右两个功能键被裁到屏幕外。
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack(alignment: .top) {
                Color.black

                AsyncImage(url: APIClient.coverURL(song?.cover)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else { Color.clear }
                }
                .frame(width: W, height: H)
                .scaleEffect(1.3)
                .blur(radius: 60)
                .saturation(1.5)
                .brightness(-0.3)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: W, height: H)

                VStack(spacing: 0) {
                    topBar
                    coverStage
                    lyricBox
                    progressBar
                    controlRow
                    functionRow
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .padding(.top, 54)
                .padding(.bottom, 34)
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
        .confirmationDialog("歌曲信息", isPresented: $showMore, titleVisibility: .visible) {
            Button("关闭") { }
        } message: {
            Text("\(song?.title ?? "—")\n\(song?.artist ?? "—")\n\(song?.album ?? "")")
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if player.isPlaying { angle += 0.9 }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            syncLyric()
        }
        .onChange(of: player.lyrics) { _ in syncLyric() }
        .onChange(of: player.currentIndex) { _ in syncLyric() }
    }

    // MARK: 顶部栏：返回键钉在最左，标题真正居中（不靠 Spacer 对称占位）
    private var topBar: some View {
        ZStack(alignment: .top) {
            HStack {
                Button { player.showFullPlayer = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            VStack(spacing: 2) {
                Text("正在播放").font(.subheadline)
                Text(song?.title ?? "—").font(.caption).opacity(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 圆形旋转封面
    @ViewBuilder
    private var coverStage: some View {
        let coverURL = APIClient.coverURL(song?.cover)
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 4))
                default:
                    Color.white.opacity(0.12).clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 4))
                }
            }
            .frame(width: 250, height: 250)
            .rotationEffect(.degrees(angle))
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: 268, height: 268)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.height < -90 { player.next() }
                    else if v.translation.height > 90 { player.prev() }
                }
        )
    }

    // MARK: 歌词
    private var lyricBox: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if player.lyrics.isEmpty {
                        Text("— 暂无歌词 —").font(.caption).opacity(0.5)
                            .id(-1)
                    }
                    ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { i, line in
                        Text(line.text.isEmpty ? "·" : line.text)
                            .font(i == lyricIndex ? .subheadline.bold() : .caption)
                            .foregroundColor(i == lyricIndex ? .white : .white.opacity(0.45))
                            .id(i)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 90)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                startPoint: .top, endPoint: .bottom))
            .onChange(of: lyricIndex) { idx in
                if idx >= 0 { withAnimation { proxy.scrollTo(idx, anchor: .center) } }
            }
        }
    }

    // MARK: 进度条（可拖动，拖动期间不被播放时钟覆盖）
    private var progressBar: some View {
        let total = max(player.duration, 1)
        return VStack(spacing: 4) {
            Slider(value: $sliderValue, in: 0...total, onEditingChanged: { editing in
                if editing {
                    seeking = true
                } else {
                    player.seek(to: sliderValue)
                    seeking = false
                }
            })
            .tint(.white)
            HStack {
                Text(fmt(min(sliderValue, total))).font(.caption2).monospacedDigit()
                Spacer()
                Text(fmt(player.duration)).font(.caption2).monospacedDigit()
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
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

    // MARK: 控制行（上一首 / 播放 / 下一首）
    private var controlRow: some View {
        HStack(spacing: 36) {
            Button { player.prev() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30)).foregroundColor(.white)
            }
            Button {
                if player.isPlaying { player.pause() } else { player.play() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.black)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Color.white))
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30)).foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: 功能行：四等分，每个按钮固定占 1/4，不依赖 Spacer 弹性
    private var functionRow: some View {
        let idx = min(max(player.playMode, 0), 2)
        let modeIcon = ["repeat", "repeat.1", "shuffle"][idx]
        let fav = song.map { player.isFav($0.id) } ?? false
        return HStack(spacing: 0) {
            fnButton(modeIcon, player.modeName) { player.cycleMode() }
            fnButton(fav ? "heart.fill" : "heart", "收藏") {
                if let s = song { player.toggleFav(s) }
            }
            fnButton("ellipsis", "更多") { showMore = true }
            fnButton("music.note.list", "列表") { player.showQueue = true }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func fnButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func syncLyric() {
        let t = player.currentTime
        var idx = -1
        for (i, l) in player.lyrics.enumerated() {
            if l.time <= t { idx = i } else { break }
        }
        if idx != lyricIndex { lyricIndex = idx }
    }
}
