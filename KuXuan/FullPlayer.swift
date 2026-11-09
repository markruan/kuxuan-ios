import SwiftUI

struct FullPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    @State private var angle: Double = 0
    @State private var lyricIndex: Int = -1

    private var song: Song? { player.current }

    var body: some View {
        ZStack {
            // 1) 兜底纯黑：彻底杜绝下层页面透出
            Color.black.ignoresSafeArea()
            // 2) 专辑封面放大 + 强模糊，作为「围着专辑图扩散」的雾化底
            //    对齐 Web .p-backdrop: filter blur(70px) saturate(1.6) brightness(.6)
            AsyncImage(url: APIClient.coverURL(song?.cover)) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else { Color.clear }
            }
            .scaleEffect(1.3)
            .blur(radius: 60)
            .saturation(1.5)
            .brightness(-0.3)
            .ignoresSafeArea()
            // 3) 暗化遮罩：保证白色文字/歌词可读，且整体不透明
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // 4) 前景内容：强制铺满，弹性 Spacer 把控制行推到底部
            VStack(spacing: 0) {
                topBar
                coverStage
                lyricBox
                controlRow
                functionRow
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.top, 54)
            .padding(.bottom, 34)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if player.showQueue { QueueSheet().transition(.move(edge: .bottom)) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.showQueue)
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if player.isPlaying { angle += 0.9 }   // 约 18 秒一圈
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            syncLyric()
        }
        .onChange(of: player.lyrics) { _ in syncLyric() }
        .onChange(of: player.currentIndex) { _ in syncLyric() }
    }

    // MARK: 顶部栏
    private var topBar: some View {
        HStack {
            Button { player.showFullPlayer = false } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundColor(.white)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放").font(.subheadline)
                Text(song?.title ?? "—").font(.caption).opacity(0.7)
            }
            Spacer()
            // 占位保持对称
            Image(systemName: "chevron.down").font(.title3).foregroundColor(.clear)
        }
        .padding(.horizontal, 18)
    }

    // MARK: 圆形旋转封面
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
            // 边缘磨砂透明光晕
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

    // MARK: 控制行（上一首 / 播放 / 下一首，居中对称）
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
        .padding(.vertical, 10)
    }

    // MARK: 功能行（循环 / 收藏 / 更多 / 列表，等距并列）
    private var functionRow: some View {
        let modeIcon = ["repeat", "repeat.1", "shuffle"][player.playMode]
        return HStack {
            Button { player.cycleMode() } label: {
                VStack(spacing: 3) {
                    Image(systemName: modeIcon).font(.system(size: 20))
                    Text(player.modeName).font(.system(size: 10))
                }
            }
            Spacer()
            Button {
                if let s = song { player.toggleFav(s) }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: (song.map { player.isFav($0.id) } ?? false) ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                    Text("收藏").font(.system(size: 10))
                }
            }
            Spacer()
            Button { /* 更多：预留 */ } label: {
                VStack(spacing: 3) {
                    Image(systemName: "ellipsis").font(.system(size: 20))
                    Text("更多").font(.system(size: 10))
                }
            }
            Spacer()
            Button { player.showQueue = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "music.note.list").font(.system(size: 20))
                    Text("列表").font(.system(size: 10))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 40)
        .padding(.top, 6)
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

private func fmt(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "0:00" }
    let i = Int(s)
    return "\(i / 60):\(String(format: "%02d", i % 60))"
}
