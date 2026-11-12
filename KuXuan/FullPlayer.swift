import SwiftUI
import UIKit

// MARK: - 全屏歌词样式（设置可选，后续可扩展）
enum LyricsStyle: String, CaseIterable, Identifiable {
    case miSide = "miSide"        // 立体掉落（miside-drop 风）
    case bilingual = "bilingual"  // 双语逐字（Folia 风：原文 + 翻译，逐字染色）+ 动感波光背景
    case vinylDisc = "vinylDisc"  // 黑胶唱片（folia-mod-vinyl-disc 风：旋转唱片 + 唱臂 + 侧边歌词）
    case aiDirector = "aiDirector" // AI 歌词导演「绘光」视觉（lyric-ai-director 预览；AI 选模式需外部 LLM，此处落地其预览的发光歌词视觉）
    case bounce = "bounce"          // 跳动歌词（Folia 默认逐字弹跳卡拉OK：当前句居中大字、逐字弹性弹入）
    var id: String { rawValue }
    var title: String {
        switch self {
        case .miSide: return "立体掉落"
        case .bilingual: return "双语逐字"
        case .vinylDisc: return "黑胶唱片"
        case .aiDirector: return "绘光"
        case .bounce:     return "跳动歌词"
        }
    }
    static var current: LyricsStyle {
        get { LyricsStyle(rawValue: UserDefaults.standard.string(forKey: "kuxuan_lyrics_style") ?? "") ?? .miSide }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "kuxuan_lyrics_style") }
    }
}

/// 进入/退出全屏歌词时的横竖屏处理（配合 AppDelegate 方向锁）
///
/// ⚠️ 不再「强制旋转」。早期实现把方向掩码锁成 `.landscape` 并调用
/// `attemptRotationToDeviceOrientation()`：当手机平放/在支架上（方向模糊）时，
/// 系统会因「掩码只允许横屏但设备是竖屏」而**持续重试旋转**，约 1 分钟后触发
/// SpringBoard 看门狗，导致整机重启（与「点返回黑屏重启」同源）。
///
/// 现改为：仅放宽方向锁，让系统按设备**实际**方向自由横竖屏；
/// 打开时允许全方向，关闭时回到竖屏锁。视图本身用 GeometryReader 自适应，无需强转。
fileprivate func setLyricsLandscape(_ on: Bool) {
    AppDelegate.orientationMask = on ? .allButUpsideDown : .portrait
}

/// 全屏歌词期间保持屏幕常亮（不自动锁屏）
fileprivate func setLyricsIdle(_ on: Bool) {
    UIApplication.shared.isIdleTimerDisabled = on
}

/// 返回：恢复竖屏锁并关闭全屏页。
/// 不再监听旋转通知或做延迟 dismiss —— 直接交还方向锁给系统，由系统平滑回到竖屏，
/// 避免任何强制旋转/重入逻辑（这是之前「点返回黑屏重启」的另一处诱因）。
fileprivate func dismissLyricsToPortrait(dismiss: @escaping () -> Void) {
    setLyricsLandscape(false)
    dismiss()
}

/// 廉价「模糊封面背景」：在小尺寸(360pt)上先算小模糊，再放大铺满全屏。
///
/// ⚠️ 关键稳定性修复：原先各样式直接对整屏高清图做 `blur(radius: 55~90)` + `scaleEffect(1.25~1.35)`，
/// 在高 DPI 下等于对「数千像素宽 × 模糊半径巨大」的渲染缓冲做 GPU 运算，极易触发 GPU 看门狗导致
/// 整机重启（下坠样式因 0.05s 定时器反复重算 body，模糊层被反复重算，秒级崩溃尤为明显）。
/// 本方法把模糊成本降到约 1/1000，视觉上仍是柔和模糊底。
fileprivate func blurredCoverBackground(url: URL?, size: CGSize) -> some View {
    Color.black
        .overlay(
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Color(white: 0.06) }
            }
            .frame(width: 360, height: 360)
            .blur(radius: 14)
            .saturation(1.3)
            .brightness(-0.35)
            .scaleEffect(max(size.width, size.height) / 360.0 * 1.15)
        )
        .frame(width: size.width, height: size.height)
        .clipped()
}

// MARK: - 颜色工具（波光取色 / 调色板）
fileprivate func rgbToHsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
    let max = Swift.max(r, g, b), min = Swift.min(r, g, b)
    let l = (max + min) / 2
    guard max != min else { return (0, 0, l) }
    let d = max - min
    let s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    let h: Double
    if max == r { h = ((g - b) / d + (g < b ? 6 : 0)) / 6 }
    else if max == g { h = ((b - r) / d + 2) / 6 }
    else { h = ((r - g) / d + 4) / 6 }
    return (h, s, l)
}
fileprivate func hueToRgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
    var t = t
    if t < 0 { t += 1 }
    if t > 1 { t -= 1 }
    if t < 1/6 { return p + (q - p) * 6 * t }
    if t < 1/2 { return q }
    if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
    return p
}
fileprivate func hslToRgb(_ h: Double, _ s: Double, _ l: Double) -> (r: Double, g: Double, b: Double) {
    guard s != 0 else { return (l, l, l) }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    return (hueToRgb(p, q, h + 1/3), hueToRgb(p, q, h), hueToRgb(p, q, h - 1/3))
}
fileprivate struct WavePalette {
    let wave: Color, bgMid: Color, bgEdge: Color, bgDeep: Color
}
fileprivate func wavePalette(_ r: Double, _ g: Double, _ b: Double) -> WavePalette {
    let (h, s, l) = rgbToHsl(r, g, b)
    let w = hslToRgb(h, min(0.9, max(0.45, s * 1.15 + 0.06)), 0.58)
    return WavePalette(
        wave: Color(.sRGB, red: w.0, green: w.1, blue: w.2, opacity: 1),
        bgMid: Color(.sRGB, red: r * 0.24, green: g * 0.24, blue: b * 0.24, opacity: 1),
        bgEdge: Color(.sRGB, red: r * 0.07, green: g * 0.07, blue: b * 0.07, opacity: 1),
        bgDeep: Color(.sRGB, red: r * 0.04, green: g * 0.04, blue: b * 0.04, opacity: 1)
    )
}

/// Color → sRGB 分量（0..1）；iOS 16 兼容（避免 Color.Resolved 仅 iOS17+）
fileprivate func resolveRGB(_ color: Color) -> (r: Double, g: Double, b: Double) {
    let ui = UIColor(color)
    var r: CGFloat = 0.4, g: CGFloat = 0.5, b: CGFloat = 1.0
    if ui.getRed(&r, green: &g, blue: &b, alpha: nil) { return (Double(r), Double(g), Double(b)) }
    return (0.4, 0.5, 1.0)
}

/// 从封面提取主色（参考 folia-mod-wave-light：24×24 降采样 + 饱和度/中间调加权），失败回退 nil
fileprivate func extractDominantColor(_ url: URL?) async -> Color? {
    guard let url = url else { return nil }
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let size = 24
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let ptr = ctx.data else { return nil }
    let px = ptr.bindMemory(to: UInt8.self, capacity: size * size * 4)
    var r = 0.0, g = 0.0, b = 0.0, sum = 0.0
    for i in 0..<(size * size) {
        let a = Double(px[i * 4 + 3])
        guard a > 160 else { continue }
        let rr = Double(px[i * 4]) / 255, gg = Double(px[i * 4 + 1]) / 255, bb = Double(px[i * 4 + 2]) / 255
        let (_, s, l) = rgbToHsl(rr, gg, bb)
        let weight = (0.08 + s * s) * max(0, 1 - abs(l - 0.5) * 1.3)
        guard weight > 0 else { continue }
        r += rr * weight; g += gg * weight; b += bb * weight; sum += weight
    }
    guard sum > 0 else { return nil }
    let (h, s, l) = rgbToHsl(r / sum, g / sum, b / sum)
    let (rr, gg, bb) = hslToRgb(h, min(0.85, max(0.42, s * 1.2 + 0.08)), min(0.62, max(0.46, l)))
    return Color(.sRGB, red: rr, green: gg, blue: bb, opacity: 1)
}

// MARK: - 动感波光背景（参考 folia-mod-wave-light：封面主色派生的暗色水面 + 左右双声波）
struct WaveLightBackground: View {
    var baseColor: Color
    var brightness: Double = 1
    var speed: Double = 1

    private static func rand(_ v: Double, _ salt: Double) -> Double {
        let x = (v + 1) * 127.1 + salt * 311.7
        let s = sin(x) * 43758.5453
        return s - floor(s)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let rgb = resolveRGB(baseColor)
                let pal = wavePalette(rgb.r, rgb.g, rgb.b)

                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.44)
                let bgGrad = Gradient(colors: [pal.bgMid, pal.bgEdge, pal.bgDeep])
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .radialGradient(bgGrad, center: center, startRadius: 0,
                                                   endRadius: hypot(size.width, size.height) * 0.62))

                context.blendMode = .plusLighter
                let wid = size.width, hgt = size.height
                let minDim = min(wid, hgt)
                let baseR = minDim * 0.62
                let t = timeline.date.timeIntervalSince1970 * speed
                let cy = hgt * (0.45 + 0.02 * sin(t * 0.09))
                let cxL = wid * 0.015 + wid * 0.012 * sin(t * 0.06 + 1.2)
                let cxR = wid * 0.985 + wid * 0.012 * sin(t * 0.055 + 3.9)
                Self.drawCluster(ctx: &context, size: size, pal: pal, cx: cxL, cy: cy, baseR: baseR, t: t, seed: 1, alphaScale: brightness)
                Self.drawCluster(ctx: &context, size: size, pal: pal, cx: cxR, cy: cy * 0.98, baseR: baseR * 1.04, t: t * 1.06, seed: 2, alphaScale: 0.92 * brightness)

                let px = wid * (0.5 + 0.18 * sin(t * 0.08 + 0.7))
                let py = hgt * (0.42 + 0.08 * cos(t * 0.06 + 2.1))
                let pr = hgt * 0.4
                let pga = Gradient(colors: [pal.wave.opacity(0.05 * brightness), pal.wave.opacity(0)])
                context.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                             with: .radialGradient(pga, center: CGPoint(x: px, y: py), startRadius: 0, endRadius: pr))

                context.blendMode = .normal
            }
        }
        .ignoresSafeArea()
    }

    private static func drawCluster(ctx: inout GraphicsContext, size: CGSize, pal: WavePalette,
                                    cx: Double, cy: Double, baseR: Double, t: Double, seed: Double, alphaScale: Double) {
        let h = size.height
        // core glow
        let coreR = baseR * 0.9
        let coreGrad = Gradient(colors: [pal.wave.opacity(0.15 * alphaScale),
                                         pal.wave.opacity(0.06 * alphaScale),
                                         pal.wave.opacity(0)])
        ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                 with: .radialGradient(coreGrad, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: coreR))

        // concentric rings with vertical banding
        let n = 9
        for i in 1...n {
            let r1 = Self.rand(Double(i) + seed * 13, 1)
            let r2 = Self.rand(Double(i) + seed * 13, 2)
            let swell = 1 + 0.15 * sin(t * (0.65 + 0.15 * r1) - Double(i) * 0.62 + seed * 2.1)
            let rr = baseR * (0.16 + 0.92 * (Double(i) / Double(n))) * swell
            let breathe = 0.6 + 0.4 * sin(t * (0.45 + 0.1 * r2) - Double(i) * 0.55 + seed)
            let alpha = max(0.008, alphaScale * (0.03 + 0.095 * (1 - Double(i) / Double(n))) * breathe)
            let topA = alpha * 0.6
            let grad = Gradient(stops: [
                .init(color: pal.wave.opacity(0), location: 0),
                .init(color: pal.wave.opacity(topA), location: 0.3),
                .init(color: pal.wave.opacity(alpha), location: 0.5),
                .init(color: pal.wave.opacity(topA), location: 0.7),
                .init(color: pal.wave.opacity(0), location: 1)
            ])
            ctx.stroke(Circle().path(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                       with: .linearGradient(grad, startPoint: CGPoint(x: cx, y: cy - rr), endPoint: CGPoint(x: cx, y: cy + rr)),
                       lineWidth: max(0.8, h * (0.0012 + 0.005 * r2)))
        }

        // sound-wave emission pulses
        for k in 0..<3 {
            let phase = (t * (0.1 + 0.018 * Self.rand(seed, 7)) + Double(k) / 3 + seed * 0.21).truncatingRemainder(dividingBy: 1)
            let rr = baseR * (0.1 + 1.04 * phase)
            let fade = pow(1 - phase, 1.6)
            let alpha = max(0.0, alphaScale * 0.17 * fade)
            if alpha > 0.004 {
                let topA = alpha * 0.6
                let grad = Gradient(stops: [
                    .init(color: pal.wave.opacity(0), location: 0),
                    .init(color: pal.wave.opacity(topA), location: 0.3),
                    .init(color: pal.wave.opacity(alpha), location: 0.5),
                    .init(color: pal.wave.opacity(topA), location: 0.7),
                    .init(color: pal.wave.opacity(0), location: 1)
                ])
                ctx.stroke(Circle().path(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                           with: .linearGradient(grad, startPoint: CGPoint(x: cx, y: cy - rr), endPoint: CGPoint(x: cx, y: cy + rr)),
                           lineWidth: max(0.8, h * (0.0018 + 0.0035 * (1 - phase))))
            }
        }

        // slowly rotating bright arcs
        for k in 0..<3 {
            let r1 = Self.rand(Double(k) + seed * 31, 4)
            let r2 = Self.rand(Double(k) + seed * 31, 6)
            let rr = baseR * (0.28 + 0.72 * r1) * (1 + 0.02 * sin(t * 0.2 + Double(k)))
            let a0 = t * (0.05 + 0.07 * r1) * (k % 2 == 1 ? -1 : 1) + Double(k) * 2.4 + seed * 1.7
            let span = 0.9 + 1.5 * r2
            let alpha = max(0.01, alphaScale * (0.09 + 0.08 * Self.rand(Double(k) + seed * 31, 5)) * (0.7 + 0.3 * sin(t * 0.3 + Double(k) * 2.2)))
            let grad = Gradient(stops: [
                .init(color: pal.wave.opacity(0), location: 0),
                .init(color: pal.wave.opacity(alpha), location: 0.5),
                .init(color: pal.wave.opacity(0), location: 1)
            ])
            var path = Path()
            path.addArc(center: CGPoint(x: cx, y: cy), radius: rr, startAngle: .radians(a0), endAngle: .radians(a0 + span), clockwise: false)
            ctx.stroke(path, with: .linearGradient(grad, startPoint: CGPoint(x: cx, y: cy - rr), endPoint: CGPoint(x: cx, y: cy + rr)),
                       lineWidth: max(1, h * (0.0018 + 0.0035 * r1)))
        }
    }
}

struct FullPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    @State private var lyricIndex: Int = -1
    @State private var showLyrics = false
    @State private var showFullLyrics = false
    @State private var lyricsFullBtnVisible = false   // 歌词页全屏按钮：出歌词时淡入、短暂后自动隐藏
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
        .overlay(alignment: .top) {
            FavSyncToast().padding(.top, safeTop + 52)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.showQueue)
        .sheet(isPresented: $showComments) {
            // 评论页要读网易云绑定态并发送评论，sheet 不会自动继承 EnvironmentObject
            CommentSheet(songID: song?.file ?? "", songTitle: song?.title ?? "")
                .environmentObject(auth)
        }
        .sheet(isPresented: $showMore) {
            // sheet 不自动继承 @EnvironmentObject，必须显式注入
            SongInfoSheet(song: song).environmentObject(auth)
        }
        .fullScreenCover(isPresented: $showFullLyrics) {
            Group {
                switch LyricsStyle.current {
                case .miSide:     MiSideLyricsView()
                case .bilingual:  FullScreenLyricsView()
                case .vinylDisc:  VinylDiscLyricsView()
                case .aiDirector: AIDirectorLyricsView()
                case .bounce:     BounceLyricsView()
                }
            }
            .environmentObject(player)
            .environmentObject(auth)
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
        blurredCoverBackground(url: APIClient.coverURL(song?.cover),
                              size: CGSize(width: W, height: H))
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
                    KXIcon(icon: .chevronDown, size: 23, color: .white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
                } label: {
                    KXIcon(icon: showLyrics ? .note : .lyric,
                           size: 20, color: .white.opacity(0.9))
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

    // MARK: 主舞台：封面 ↔ 歌词（交叉淡入，不再硬切）
    @ViewBuilder
    private var stage: some View {
        ZStack {
            if showLyrics {
                lyricsStage
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                coverStage
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: 圆形旋转封面 + 下方 1-2 行动态歌词预览
    @ViewBuilder
    private var coverStage: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                // 旋转状态收在独立子视图里，父级 FullPlayer.body 不再被定时器反复重算
                RotatingAlbumCover(url: APIClient.coverURL(song?.cover),
                                   isPlaying: player.isPlaying)
                    .frame(maxWidth: .infinity)
                lyricPreview
                    .frame(height: 48)
                Spacer(minLength: 0)
            }
            // 主播放页封面不再常驻全屏按钮；全屏入口改到「点封面出歌词后」的歌词页右上角（上下文淡入、不常驻）

        }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.height < -90 { player.next() }
                else if v.translation.height > 90 { player.prev() }
            }
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.28)) { showLyrics = true }
        }
    }

    /// 封面下方常驻 1-2 行歌词：当前行 + 下一行，随播放逐行上滑切换；
    /// 点击任意位置进入全屏歌词页。没有歌词时给占位文案，不留空白。
    private var lyricPreview: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) { showLyrics = true }
        } label: {
            VStack(spacing: 5) {
                if player.lyrics.isEmpty {
                    Text("暂无歌词 · 纯音乐，请欣赏")
                        .font(.caption).foregroundColor(.white.opacity(0.45))
                } else {
                    let i = max(0, min(lyricIndex, player.lyrics.count - 1))
                    let cur = player.lyrics[i].text
                    let nxt = (i + 1 < player.lyrics.count) ? player.lyrics[i + 1].text : ""
                    Text(cur.isEmpty ? "·" : cur)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.94))
                        .lineLimit(1)
                        .id("preview-\(i)")
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)))
                    if !nxt.isEmpty {
                        Text(nxt)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.40))
                            .lineLimit(1)
                            .id("preview-next-\(i)")
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.34), value: lyricIndex)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 歌词：占满整块主舞台，逐行高亮 + 自动滚到中央 + 点击跳转
    @ViewBuilder
    private var lyricsStage: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        Spacer().frame(height: 130)
                        if player.lyrics.isEmpty {
                            VStack(spacing: 10) {
                                KXIcon(icon: .note, size: 30, color: .white.opacity(0.5))
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
                            }
                        }
                        Spacer().frame(height: 130)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showLyrics = false }
                    }
                }
                .mask(LinearGradient(colors: [.clear, .black.opacity(0.85), .black, .black.opacity(0.85), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .onAppear { scrollLyric(proxy) }
                .onChange(of: lyricIndex) { _ in scrollLyric(proxy) }
                .onChange(of: showLyrics) { _ in scrollLyric(proxy) }
                .onChange(of: player.lyrics) { _ in scrollLyric(proxy) }
            }
            // 全屏歌词按钮：点封面出歌词时淡入，2.5s 后自动隐藏（不常驻，避免遮挡/丑）；点它进全屏歌词
            Button { showFullLyrics = true } label: {
                KXIcon(icon: .expand, size: 18, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .contentShape(Circle())
            .opacity(lyricsFullBtnVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: lyricsFullBtnVisible)
            .onAppear {
                lyricsFullBtnVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    lyricsFullBtnVisible = false
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
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
        let thumbD: CGFloat = 10   // 小圆点：约为系统 Slider 默认(≈28)的 1/3
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let frac = CGFloat(min(max(sliderValue, 0), total)) / CGFloat(total)
                let cx = max(thumbD / 2, min(w - thumbD / 2, w * frac))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                        .frame(width: w, height: 4)
                    Capsule().fill(Color.white)
                        .frame(width: max(0, w * frac), height: 4)
                    Circle().fill(Color.white)
                        .frame(width: thumbD, height: thumbD)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .position(x: cx, y: h / 2)
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            seeking = true
                            let p = max(0, min(1, v.location.x / w))
                            sliderValue = Double(p) * total
                        }
                        .onEnded { _ in
                            player.seek(to: sliderValue)
                            seeking = false
                        }
                )
            }
            .frame(height: 26)   // 留足拖拽命中区，但圆点本身只有 10pt
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
        HStack(spacing: 48) {
            skipButton("backward.fill") { player.prev() }
            Button {
                if player.isPlaying { player.pause() } else { player.play() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            skipButton("forward.fill") { player.next() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// 上一曲/下一曲：改用 SF Symbols（Apple 原生），与中央播放键清晰区分，不再与播放按钮混淆
    private func skipButton(_ sfSymbol: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sfSymbol)
                .font(.system(size: 30, weight: .black))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
    }

    // MARK: 功能行（5 等分，全部钉在宽度内）
    private var functionRow: some View {
        let idx = min(max(player.playMode, 0), 2)
        let modeIcon: KXIconName = [.repeatAll, .repeatOne, .shuffle][idx]
        let fav = song.map { player.isFav($0.id) } ?? false
        return HStack(spacing: 0) {
            fnButton(modeIcon, player.modeName) { player.cycleMode() }
            fnButton(fav ? .heartFill : .heart, "收藏") {
                if let s = song { player.toggleFav(s) }
            }
            fnButton(.comment, "评论") { showComments = true }
            fnButton(.list, "列表") { player.showQueue = true }
            fnButton(.more, "更多") { showMore = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func fnButton(_ icon: KXIconName, _ title: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                KXIcon(icon: icon, size: 19, color: .white)
                Text(title).font(.system(size: 10)).lineLimit(1).foregroundColor(.white)
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

// MARK: - 全屏歌词（Folia 风：模糊封面背景 + 左对齐逐字高亮 + 活跃行放大居中 + 点按跳转）
struct FullScreenLyricsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var tick: Double = 0
    @State private var tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { player.lyrics }
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

    // 横屏时摄像头/灵动岛在某一侧，需读取 left/right 安全区避免歌词被遮挡
    private var safeLeading: CGFloat { windowSafeInset(\.left) }
    private var safeTrailing: CGFloat { windowSafeInset(\.right) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                WaveLightBackground(baseColor: Color(player.coverColor))
                    .frame(width: geo.size.width, height: geo.size.height)
                shadeLayer(geo.size)
                lyricsList
                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { tick = player.currentTime; recompute(); setLyricsLandscape(true); setLyricsIdle(true) }
        .onReceive(tickTimer) { _ in
            let nt = player.currentTime
            guard abs(nt - tick) > 0.02 else { return }
            tick = nt
            recompute()
        }
        .onDisappear { setLyricsLandscape(false); setLyricsIdle(false) }
    }

    // MARK: 背景（复用全屏播放器同款模糊封面）
    private func backgroundLayer(_ size: CGSize) -> some View {
        blurredCoverBackground(url: APIClient.coverURL(player.current?.cover), size: size)
        .clipped()
    }

    private func shadeLayer(_ size: CGSize) -> some View {
        LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.55)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { dismissLyricsToPortrait { dismiss() } } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.top, safeTop + 4)
        .padding(.leading, max(safeLeading + 16, 32))
        .padding(.trailing, 16)
    }

    // MARK: 歌词列表
    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer().frame(height: max(safeTop + 130, 170))
                    if lines.isEmpty {
                        VStack(spacing: 10) {
                            KXIcon(icon: .note, size: 30, color: .white.opacity(0.5))
                            Text("暂无歌词").font(.subheadline).opacity(0.6)
                            Text("纯音乐，请欣赏").font(.caption).opacity(0.4)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .id(-1)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            lineView(i, line)
                                .id(i)
                                .onTapGesture {
                                    player.seek(to: line.time)
                                    tick = line.time
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        proxy.scrollTo(i, anchor: .center)
                                    }
                                }
                        }
                    }
                    Spacer().frame(height: max(safeBottom + 160, 220))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, max(safeLeading + 52, 84))
                .padding(.trailing, max(safeTrailing + 24, 40))
            }
            .mask(LinearGradient(colors: [.clear, .black.opacity(0.9), .black, .black.opacity(0.9), .clear],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear { scrollTo(proxy) }
            .onChange(of: activeIndex) { _ in scrollTo(proxy) }
        }
    }

    private func lineView(_ i: Int, _ line: LyricLine) -> some View {
        let isActive = i == activeIndex
        let isPast = i < activeIndex
        return VStack(alignment: .leading, spacing: 6) {
            if line.words.isEmpty {
                Text(line.text.isEmpty ? "·" : line.text)
                    .font(isActive ? .system(size: 23, weight: .bold)
                                   : .system(size: 17, weight: .medium))
                    .foregroundColor(isActive ? .white
                                     : (isPast ? accentColor.opacity(0.62) : .white.opacity(0.32)))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                wordLine(line, isActive: isActive, isPast: isPast)
                    .font(isActive ? .system(size: 23, weight: .bold)
                                   : .system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isActive, !line.translation.isEmpty {
                Text(line.translation)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scaleEffect(isActive ? 1.04 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    /// 强调色：取封面主色并提亮增饱和，用于「逐字染色」
    private var accentColor: Color {
        let ui = player.coverColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h),
                     saturation: min(1, Double(s) * 1.5 + 0.1),
                     brightness: min(1, Double(b) * 0.4 + 0.6),
                     opacity: 1)
    }

    private func wordProgress(_ w: LyricWord) -> Double {
        if tick >= w.time + w.duration { return 1 }
        if tick <= w.time { return 0 }
        return (tick - w.time) / max(w.duration, 0.001)
    }

    /// 逐字染色（Folia 双语风）：随播放进度由暗白渐变为强调色，已唱过的字染色更鲜明
    private func wordLine(_ line: LyricLine, isActive: Bool, isPast: Bool) -> some View {
        let combined = line.words.reduce(Text("")) { acc, w in
            acc + Text(w.text).foregroundColor(wordColor(w, active: isActive, past: isPast))
        }
        return combined
    }

    private func wordColor(_ w: LyricWord, active: Bool, past: Bool) -> Color {
        if !active { return past ? accentColor.opacity(0.62) : Color.white.opacity(0.34) }
        let p = wordProgress(w)
        if p <= 0 { return Color.white.opacity(0.34) }
        if p >= 1 { return accentColor }
        return accentColor.opacity(0.34 + 0.66 * p)
    }

    private func scrollTo(_ proxy: ScrollViewProxy) {
        guard activeIndex >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(activeIndex, anchor: .center)
        }
    }

    /// 二分查找当前活跃行；歌曲开始前默认高亮首行，避免整屏空白
    private func recompute() {
        let ls = lines
        guard !ls.isEmpty else {
            if activeIndex != -1 { activeIndex = -1 }
            return
        }
        let t = tick
        var lo = 0, hi = ls.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ls[mid].time <= t { found = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        if found < 0 { found = 0 }
        if found != activeIndex { activeIndex = found }
    }
}

// MARK: - 共享：读取关键窗口的安全区插入（处理横屏摄像头遮挡）
fileprivate func windowSafeInset(_ key: KeyPath<UIEdgeInsets, CGFloat>) -> CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?.safeAreaInsets[keyPath: key] ?? 0
}

// MARK: - 黑胶唱片全屏歌词（参考 folia-mod-vinyl-disc）
struct VinylDiscLyricsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var tick: Double = 0
    @State private var tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { player.lyrics }
    private let rotationSeconds: Double = 20
    private let coverPercent: CGFloat = 0.72
    private let discPercent: CGFloat = 0.60

    private var safeTop: CGFloat { windowSafeInset(\.top) }
    private var safeBottom: CGFloat { windowSafeInset(\.bottom) }
    private var safeLeading: CGFloat { windowSafeInset(\.left) }
    private var safeTrailing: CGFloat { windowSafeInset(\.right) }

    var body: some View {
        GeometryReader { geo in
            let disc = min(geo.size.width, geo.size.height) * discPercent
            ZStack(alignment: .topLeading) {
                backgroundLayer(geo.size)
                HStack(alignment: .center, spacing: 0) {
                    lyricsLayer(geo)
                        .frame(maxWidth: .infinity)
                    discOnly(disc)
                        .frame(width: disc * 1.2, height: disc * 1.2)
                        .padding(.trailing, max(24 + safeTrailing, geo.size.width * 0.06))
                }
                .padding(.leading, 24 + safeLeading)
                .padding(.top, safeTop)
                .padding(.bottom, safeBottom)
                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            tick = player.currentTime; activeIndex = findIndex(tick)
            setLyricsLandscape(true); setLyricsIdle(true)
        }
        .onReceive(tickTimer) { _ in
            let nt = player.currentTime
            guard abs(nt - tick) > 0.02 else { return }
            tick = nt
            driveIndex()
        }
        .onDisappear { setLyricsLandscape(false); setLyricsIdle(false) }
    }

    private func findIndex(_ t: Double) -> Int {
        let ls = lines
        guard !ls.isEmpty else { return -1 }
        var lo = 0, hi = ls.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ls[mid].time <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found < 0 ? 0 : found
    }
    private func driveIndex() {
        let cur = findIndex(tick)
        if cur != activeIndex { activeIndex = cur }
    }

    private func backgroundLayer(_ size: CGSize) -> some View {
        blurredCoverBackground(url: APIClient.coverURL(player.current?.cover), size: size).opacity(0.22)
    }

    // MARK: 歌词（QQ 音乐式：当前句加粗高亮，前后随距离淡出缩小；翻译附于当前句下）
    private func lyricsLayer(_ geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Spacer().frame(height: safeTop + geo.size.height * 0.22)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        lineCell(i, line)
                            .id(i)
                            .onTapGesture {
                                player.seek(to: line.time); tick = line.time
                                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(i, anchor: .center) }
                            }
                    }
                    Spacer().frame(height: safeBottom + geo.size.height * 0.22)
                }
                .padding(.horizontal, 8)
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .onAppear { withAnimation { proxy.scrollTo(activeIndex, anchor: .center) } }
            .onChange(of: activeIndex) { _ in
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(activeIndex, anchor: .center) }
            }
        }
    }

    private func lineCell(_ i: Int, _ line: LyricLine) -> some View {
        let isActive = i == activeIndex
        let dist = abs(i - max(activeIndex, 0))
        let scale = isActive ? 1.0 : max(0.82, 1 - Double(dist) * 0.05)
        let opacity = isActive ? 1.0 : max(0.25, 1 - Double(dist) * 0.18)
        return HStack(alignment: .top, spacing: 8) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: 22)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                if line.words.isEmpty {
                    Text(line.text.isEmpty ? "·" : line.text)
                        .font(.system(size: isActive ? 22 : 17, weight: isActive ? .bold : .medium))
                } else {
                    wordLine(line, active: isActive)
                        .font(.system(size: isActive ? 22 : 17, weight: isActive ? .bold : .medium))
                }
                if isActive, !line.translation.isEmpty {
                    Text(line.translation).font(.system(size: 13)).foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .foregroundColor(isActive ? accentColor : .white)
        .opacity(opacity)
        .scaleEffect(scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private func accent(_ o: Double = 1) -> Color {
        let ui = player.coverColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h),
                     saturation: min(1, Double(s) * 1.5 + 0.1),
                     brightness: min(1, Double(b) * 0.4 + 0.6),
                     opacity: o)
    }
    private var accentColor: Color { accent() }
    private func wordProgress(_ w: LyricWord) -> Double {
        if tick >= w.time + w.duration { return 1 }
        if tick <= w.time { return 0 }
        return (tick - w.time) / max(w.duration, 0.001)
    }
    private func wordColor(_ w: LyricWord, active: Bool) -> Color {
        if !active { return Color.white.opacity(0.45) }
        let p = wordProgress(w)
        if p <= 0 { return Color.white.opacity(0.45) }
        if p >= 1 { return accentColor }
        return accentColor.opacity(0.45 + 0.55 * p)
    }
    private func wordLine(_ line: LyricLine, active: Bool) -> Text {
        line.words.reduce(Text("")) { acc, w in
            acc + Text(w.text).foregroundColor(wordColor(w, active: active))
        }
    }

    // MARK: 黑胶（已移除唱臂；旋转隔离到 VinylRotatingDisc 子视图，避免整页重绘抖动）
    private func discOnly(_ d: CGFloat) -> some View {
        VinylRotatingDisc(d: d, coverURL: APIClient.coverURL(player.current?.cover))
    }

    // 唱臂已移除；唱片旋转隔离到下方 VinylRotatingDisc 子视图（消除整页重绘抖动）

// MARK: - 黑胶旋转（独立子视图）
/// 平滑化要点：
/// 1) 角度按「真实经过时间 dt」累计（accumulated += degPerSec * dt），而非固定步进，
///    掉帧/定时器漂移时自动补偿，不再忽快忽慢；
/// 2) 60fps 定时器，与屏幕刷新更接近；
/// 3) 暂停时冻结角度（last 仍更新，恢复时无跳变）；
/// 4) 去掉 .compositingGroup()，改由 GPU 直接整层变换，消除逐帧重栅格化的微闪。
private struct VinylRotatingDisc: View {
    let d: CGFloat
    let coverURL: URL?
    @EnvironmentObject var player: PlayerEngine
    private let rotationSeconds: Double = 4.8          // 一圈约 4.8 秒
    private var degPerSec: Double { 360 / rotationSeconds }

    @State private var accumulated: Double = 0
    @State private var last: Date = Date()
    @State private var ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DiscArt(d: d, coverURL: coverURL)
            .frame(width: d, height: d)
            .rotationEffect(.degrees(accumulated))
            .onReceive(ticker) { now in
                let dt = now.timeIntervalSince(last)
                last = now
                guard player.isPlaying else { return }
                accumulated += degPerSec * dt
                if accumulated >= 360 { accumulated -= 360 }
            }
    }
}

// 静态唱片画面（与旋转角度无关，避免每帧重建渐变/沟槽）
private struct DiscArt: View {
    let d: CGFloat
    let coverURL: URL?
    private let coverPercent: CGFloat = 0.40   // 真实黑胶中心标贴约占 1/3 盘面

    var body: some View {
        ZStack {
            // 盘体：深黑 + 细微径向渐变营造厚度
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.12), Color(white: 0.02)],
                                    center: .center, startRadius: d * 0.12, endRadius: d * 0.5))
                .shadow(color: .black.opacity(0.65), radius: d * 0.12, x: 0, y: d * 0.05)
            // 沟槽：细密同心圆环
            ForEach(0..<14, id: \.self) { i in
                let r = d * (0.48 - 0.028 * Double(i))
                Circle().stroke(Color.white.opacity(0.045), lineWidth: 1)
                    .frame(width: r * 2, height: r * 2)
            }
            // 镜面高光弧（转盘反射）
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear,
                                               .white.opacity(0.06), .clear],
                                     center: .center))
                .frame(width: d, height: d)
            // 中心标贴（专辑封面）
            AsyncImage(url: coverURL) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Color(white: 0.16) }
            }
            .frame(width: d * coverPercent, height: d * coverPercent)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: d * 0.012))
            // 中心孔
            Circle().fill(Color.black).frame(width: d * 0.03, height: d * 0.03)
        }
    }
}


    private var topBar: some View {
        HStack(spacing: 0) {
            Button { dismissLyricsToPortrait { dismiss() } } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .white).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.top, safeTop + 4)
        .padding(.leading, 16 + safeLeading)
    }
}

// MARK: - AI 歌词导演「绘光」全屏歌词（参考 lyric-ai-director 预览的发光歌词视觉）
/// 注：原模组是「用 LLM 为每首歌选模式+调参」，需外部 API 密钥，无法在本地离线运行；
/// 此处落地其预览中可见的「绘光」视觉——深蓝黑底、左侧镜头光晕/星芒、彩虹光束、漂浮光尘、
/// 居中发光歌词（当前句白光+蓝色辉光，前后句渐隐）。
struct AIDirectorLyricsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var tick: Double = 0
    @State private var tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { player.lyrics }
    private var safeTop: CGFloat { windowSafeInset(\.top) }
    private var safeBottom: CGFloat { windowSafeInset(\.bottom) }
    private var safeLeading: CGFloat { windowSafeInset(\.left) }
    private var safeTrailing: CGFloat { windowSafeInset(\.right) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black
                AIBackground(size: geo.size)
                centeredLyrics(geo)
                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { tick = player.currentTime; activeIndex = findIndex(tick); setLyricsLandscape(true); setLyricsIdle(true) }
        .onReceive(tickTimer) { _ in
            let nt = player.currentTime
            guard abs(nt - tick) > 0.02 else { return }
            tick = nt
            driveIndex()
        }
        .onDisappear { setLyricsLandscape(false); setLyricsIdle(false) }
    }

    private func findIndex(_ t: Double) -> Int {
        let ls = lines
        guard !ls.isEmpty else { return -1 }
        var lo = 0, hi = ls.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ls[mid].time <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found < 0 ? 0 : found
    }
    private func driveIndex() {
        let cur = findIndex(tick)
        if cur != activeIndex { activeIndex = cur }
    }

    // MARK: 居中发光歌词
    private func centeredLyrics(_ geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer().frame(height: safeTop + geo.size.height * 0.32)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        aiLineCell(i, line).id(i)
                            .onTapGesture {
                                player.seek(to: line.time); tick = line.time
                                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(i, anchor: .center) }
                            }
                    }
                    Spacer().frame(height: safeBottom + geo.size.height * 0.32)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24 + safeLeading + safeTrailing)
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .onChange(of: activeIndex) { _ in
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(activeIndex, anchor: .center) }
            }
        }
    }

    private func aiLineCell(_ i: Int, _ line: LyricLine) -> some View {
        let isActive = i == activeIndex
        let dist = abs(i - max(activeIndex, 0))
        let opacity = isActive ? 1.0 : max(0.22, 1 - Double(dist) * 0.22)
        let accent = Color(hue: 0.55, saturation: 0.9, brightness: 1)
        return VStack(spacing: 6) {
            AILightLine(line: line, active: isActive, tick: tick)
            if isActive, !line.translation.isEmpty {
                Text(line.translation)
                    .font(.system(size: 15))
                    .foregroundColor(accent.opacity(0.85))
            }
        }
        .foregroundColor(.white)
        .opacity(opacity)
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(color: accent.opacity(isActive ? 0.9 : 0), radius: isActive ? 16 : 0)
        .animation(.easeInOut(duration: 0.35), value: isActive)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { dismissLyricsToPortrait { dismiss() } } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .white).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.top, safeTop + 4)
        .padding(.leading, 16 + safeLeading)
    }
}

// 绘光背景：深蓝黑底 + 左侧镜头光晕/星芒 + 彩虹光束 + 漂浮光尘（加法混合动画）
struct AIBackground: View {
    let size: CGSize
    static func rand(_ v: Double, _ s: Double) -> Double {
        let x = (v + 1) * 127.1 + s * 311.7
        let z = sin(x) * 43758.5453
        return z - floor(z)
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSince1970
                // 基础辉光
                let glow = Gradient(colors: [Color(hue: 0.58, saturation: 0.8, brightness: 0.5).opacity(0.45), .clear])
                ctx.fill(Path(CGRect(origin: .zero, size: sz)),
                         with: .radialGradient(glow, center: CGPoint(x: sz.width * 0.5, y: sz.height * 0.5),
                                              startRadius: 0, endRadius: max(sz.width, sz.height) * 0.7))
                ctx.blendMode = .plusLighter
                // 左侧镜头光晕核心
                let fx = sz.width * 0.12, fy = sz.height * 0.5
                let core = Gradient(colors: [Color.white.opacity(0.9), Color(hue: 0.55, saturation: 0.9, brightness: 1).opacity(0)])
                ctx.fill(Path(ellipseIn: CGRect(x: fx - 60, y: fy - 60, width: 120, height: 120)),
                         with: .radialGradient(core, center: CGPoint(x: fx, y: fy), startRadius: 0, endRadius: 70))
                // 星芒（缓慢旋转）
                for k in 0..<8 {
                    let a = Double(k) / 8 * .pi * 2 + t * 0.05
                    var p = Path()
                    p.move(to: CGPoint(x: fx, y: fy))
                    p.addLine(to: CGPoint(x: fx + Foundation.cos(a) * sz.width * 0.5, y: fy + Foundation.sin(a) * sz.height * 0.5))
                    ctx.stroke(p, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)]),
                                                       startPoint: CGPoint(x: fx, y: fy), endPoint: CGPoint(x: fx + sz.width, y: fy)), lineWidth: 1)
                }
                // 彩虹光束（斜向，主）
                var beam = Path()
                beam.move(to: CGPoint(x: 0, y: sz.height * 0.32))
                beam.addLine(to: CGPoint(x: sz.width, y: sz.height * 0.5))
                beam.addLine(to: CGPoint(x: sz.width, y: sz.height * 0.62))
                beam.addLine(to: CGPoint(x: 0, y: sz.height * 0.44))
                let rainbow = Gradient(colors: [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple]
                                        .map { $0.opacity(0.12) })
                ctx.fill(beam, with: .linearGradient(rainbow, startPoint: CGPoint(x: 0, y: 0),
                                                    endPoint: CGPoint(x: sz.width, y: sz.height)))
                // 体积光束（更宽更柔，缓慢横移）
                var shaft = Path()
                let off = 0.04 * Foundation.sin(t * 0.1)
                shaft.move(to: CGPoint(x: 0, y: sz.height * (0.18 + off)))
                shaft.addLine(to: CGPoint(x: sz.width, y: sz.height * (0.34 + off)))
                shaft.addLine(to: CGPoint(x: sz.width, y: sz.height * (0.52 + off)))
                shaft.addLine(to: CGPoint(x: 0, y: sz.height * (0.36 + off)))
                ctx.fill(shaft, with: .linearGradient(Gradient(colors: [Color(hue: 0.55, saturation: 0.9, brightness: 1).opacity(0.10), .clear]),
                                                     startPoint: CGPoint(x: 0, y: sz.height * 0.3),
                                                     endPoint: CGPoint(x: 0, y: sz.height * 0.5)))
                // 漂浮光尘（带闪烁）
                for i in 0..<42 {
                    let seed = Double(i)
                    let x = Self.rand(seed + 1, 3) + 0.25 * Foundation.sin(t * 0.2 + seed)
                    let y = Self.rand(seed, 7) + 0.2 * Foundation.cos(t * 0.15 + seed)
                    let px = (x.truncatingRemainder(dividingBy: 1)) * sz.width
                    let py = (y.truncatingRemainder(dividingBy: 1)) * sz.height
                    let rad = 1 + Self.rand(seed, 2) * 2
                    let tw = 0.35 + 0.65 * (0.5 + 0.5 * Foundation.sin(t * 0.9 + seed * 2.3))
                    let col = Color(hue: 0.55 + 0.1 * Foundation.sin(seed), saturation: 0.8, brightness: 1).opacity(0.5 * tw)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - rad, y: py - rad, width: rad * 2, height: rad * 2)),
                             with: .radialGradient(Gradient(colors: [col, col]), center: CGPoint(x: px, y: py), startRadius: 0, endRadius: max(rad, 0.5)))
                }
                ctx.blendMode = .normal
                // 暗角（电影感）
                let vig = Gradient(colors: [Color.clear, Color.black.opacity(0.55)])
                ctx.fill(Path(CGRect(origin: .zero, size: sz)),
                         with: .radialGradient(vig, center: CGPoint(x: sz.width * 0.5, y: sz.height * 0.5),
                                              startRadius: min(sz.width, sz.height) * 0.28,
                                              endRadius: max(sz.width, sz.height) * 0.72))
            }
        }
        .ignoresSafeArea()
    }
}

/// 绘光当前句：被光「描绘」的横向扫光 + 逐字染青白（参考 lyric-ai-director 的发光歌词）
fileprivate struct AILightLine: View {
    let line: LyricLine
    let active: Bool
    let tick: Double
    @State private var sweep: CGFloat = -0.6
    private let accent = Color(hue: 0.55, saturation: 0.9, brightness: 1)

    private func wp(_ w: LyricWord) -> Double {
        if tick >= w.time + w.duration { return 1 }
        if tick <= w.time { return 0 }
        return (tick - w.time) / max(w.duration, 0.001)
    }
    private func wColor(_ w: LyricWord) -> Color {
        if !active { return Color.white.opacity(0.5) }
        let p = wp(w)
        if p <= 0 { return Color.white.opacity(0.5) }
        if p >= 1 { return accent }
        return accent.opacity(0.5 + 0.5 * p)
    }
    private var base: Text {
        line.words.isEmpty
            ? Text(line.text.isEmpty ? "·" : line.text)
            : line.words.reduce(Text("")) { acc, w in acc + Text(w.text).foregroundColor(wColor(w)) }
    }
    var body: some View {
        let font = Font.system(size: active ? 30 : 20, weight: .bold)
        return ZStack {
            base.font(font)
                .foregroundColor(.white)
                .opacity(active ? 1 : 0.5)
            if active {
                base.font(font)
                    .overlay(
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 240)
                            .offset(x: sweep * 360)
                            .blendMode(.plusLighter)
                    )
                    .mask(base.font(font))
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { sweep = 0.6 }
                    }
            }
        }
    }
}

// MARK: - MiSide 立体掉落全屏歌词（横屏大图风）
/// 参考 miside-drop（Folia/Folium 模组）：打字机逐字浮现 → 整句坠落（重力触底反弹+翻滚）
/// → 灰阶立体挤出（7 层 text-shadow 厚度）→ 落地停留 2.5s → 1.5s 淡出。地面高度可调。
struct MiSideLyricsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var tick: Double = 0
    @State private var fallingIndex: Int = -1
    @State private var fallProgress: CGFloat = 0
    @State private var fallRot: Double = 0
    @State private var fallOpacity: Double = 1
    @State private var fallTimer: Timer? = nil
    /// 落句文本快照：triggerFall 时把「落下那句」已完整显示的文本缓存，
    /// 落字动画（约 4 秒）期间不再每帧重算 typewriterText（reduce 重建整段文本树），进一步降压。
    @State private var fallingText: Text? = nil
    /// 稳定计时器：视图实例创建一次，避免内联 Timer.publish 在每次 body 重算时反复重订阅
    /// （此前下坠样式因此被 0.05s 高频重建拖垮渲染服务，整机重启）
    @State private var tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { player.lyrics }
    private var groundRatio: CGFloat { 0.82 }

    var body: some View {
        GeometryReader { geo in
            let groundY = geo.size.height * groundRatio
            let spawnY = geo.size.height * 0.34
            ZStack(alignment: .top) {
                backgroundLayer(geo.size)
                shadeLayer(geo.size)
                stage(geo, spawnY: spawnY, groundY: groundY)
                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { tick = player.currentTime; activeIndex = findIndex(tick); setLyricsLandscape(true); setLyricsIdle(true) }
        .onReceive(tickTimer) { _ in
            // currentTime 每 0.5s 才由播放器更新一次；过滤无变化的采样，
            // 把视图重建从 20 次/秒降到约 2 次/秒，根治渲染服务看门狗重启
            let nt = player.currentTime
            guard abs(nt - tick) > 0.02 else { return }
            tick = nt
            drive()
        }
        .onDisappear { fallTimer?.invalidate(); setLyricsLandscape(false); setLyricsIdle(false) }
    }

    private func stage(_ geo: GeometryProxy, spawnY: CGFloat, groundY: CGFloat) -> some View {
        ZStack {
            if lines.isEmpty {
                VStack(spacing: 10) {
                    KXIcon(icon: .note, size: 30, color: .white.opacity(0.5))
                    Text("暂无歌词").font(.subheadline).opacity(0.6)
                    Text("纯音乐，请欣赏").font(.caption).opacity(0.4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if fallingIndex >= 0, fallingIndex < lines.count {
                    VStack(spacing: 6) {
                        extruded(fallingText ?? typewriterText(lines[fallingIndex]))
                            .opacity(fallOpacity)
                            .font(.system(size: 26, weight: .bold))
                        if !lines[fallingIndex].translation.isEmpty {
                            Text(lines[fallingIndex].translation)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5 * fallOpacity))
                        }
                    }
                    .position(x: geo.size.width / 2,
                              y: spawnY + (groundY - spawnY) * fallProgress)
                    .rotationEffect(.degrees(fallRot))
                }
                if activeIndex >= 0, activeIndex < lines.count {
                    // v2：上面大行——文字多到两行时仍保持尽量大字号（minimumScaleFactor=1 不自动缩小），
                    // 允许自然换行；下坠行（fallingIndex）字号保持 26 不变。
                    VStack(spacing: 6) {
                        extruded(typewriterText(lines[activeIndex]))
                            .font(.system(size: 32, weight: .bold))
                            .lineLimit(nil)
                            .minimumScaleFactor(1.0)
                            .fixedSize(horizontal: false, vertical: true)
                        if !lines[activeIndex].translation.isEmpty {
                            Text(lines[activeIndex].translation)
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(nil)
                                .minimumScaleFactor(1.0)
                        }
                    }
                    .position(x: geo.size.width / 2, y: spawnY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 灰阶立体挤出：7 层硬边阴影（黑色偏移）叠出实体厚度；不改前景色，
    /// 因此 Text 内部的逐字透明（打字机未出现字）自然无阴影，厚度只作用在可见字上。
    ///
    /// ⚠️ 稳定性修复（v37）：7 层 `.shadow()` 每层都是一次离屏渲染 pass，落字动画
    /// （position/rotation/opacity 由 withAnimation 驱动，持续约 4 秒）每帧都要重合成这 7 层，
    /// 触发 backboardd 看门狗 → 整机重启。这是下坠独有的负担（其他三样式不用 extruded，
    /// 主播放页用相同 backgroundLayer/shadeLayer 也不崩，反证根因在此）。
    ///
    /// v36 误用 `.compositingGroup()`（只做混合分组，不阻止阴影逐帧重算），仍崩。
    /// 改为 `.drawingGroup()`：把「7 层阴影 + 文本」**光栅化成单张离屏位图**，落字动画
    /// 只移动/旋转/淡出这张位图，GPU 不再每帧重算阴影路径 —— 视觉（7 层立体厚度）完全保留。
    private func extruded(_ text: Text) -> some View {
        text
            .shadow(color: .black.opacity(0.55), radius: 0, x: 1, y: 1)
            .shadow(color: .black.opacity(0.50), radius: 0, x: 2, y: 2)
            .shadow(color: .black.opacity(0.45), radius: 0, x: 3, y: 3)
            .shadow(color: .black.opacity(0.40), radius: 0, x: 4, y: 4)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 5, y: 5)
            .shadow(color: .black.opacity(0.30), radius: 0, x: 6, y: 6)
            .shadow(color: .black.opacity(0.25), radius: 0, x: 7, y: 7)
            .drawingGroup()
    }

    /// 打字机逐字浮现：每字按其歌词绝对时间出现（未出现用透明前景，保留布局占位）
    private func typewriterText(_ line: LyricLine) -> Text {
        if line.words.isEmpty {
            return Text(line.text.isEmpty ? "·" : line.text)
        }
        return line.words.reduce(Text("")) { acc, w in
            let appeared = tick >= w.time
            return acc + Text(w.text).foregroundColor(appeared ? .white : .clear)
        }
    }

    private func drive() {
        let ls = lines
        guard !ls.isEmpty else { activeIndex = -1; return }
        let cur = findIndex(tick)
        if cur != activeIndex {
            if activeIndex >= 0, activeIndex != fallingIndex {
                triggerFall(activeIndex)
            }
            activeIndex = cur
        }
        if activeIndex >= 0, tick >= lineEndTime(activeIndex), activeIndex != fallingIndex {
            triggerFall(activeIndex)
            activeIndex = -1
        }
    }

    private func triggerFall(_ i: Int) {
        guard i >= 0, i < lines.count else { return }
        if i == fallingIndex { return }
        fallingIndex = i
        fallingText = typewriterText(lines[i])   // 该句此时已整句显示完毕（tick 已越过其末尾），快照安全
        fallProgress = 0
        fallRot = 0
        fallOpacity = 1
        // 重力坠落：先加速下落（自由落体感）
        withAnimation(.timingCurve(0.5, 0.0, 1.0, 1.0, duration: 0.55)) {
            fallProgress = 1
        }
        // 触底翻滚
        withAnimation(.interpolatingSpring(stiffness: 110, damping: 8, initialVelocity: 0)) {
            fallRot = Double.random(in: -24...24)
        }
        // 落地轻微回弹（下沉 → 回弹 → 落定）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.16)) { fallProgress = 0.965 }
            withAnimation(.easeInOut(duration: 0.22).delay(0.16)) { fallProgress = 1 }
        }
        fallTimer?.invalidate()
        fallTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 1.5)) { fallOpacity = 0 }
        }
    }

    private func findIndex(_ t: Double) -> Int {
        let ls = lines
        guard !ls.isEmpty else { return -1 }
        var lo = 0, hi = ls.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ls[mid].time <= t { found = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return found < 0 ? 0 : found
    }

    private func lineEndTime(_ i: Int) -> Double {
        let ls = lines
        if i + 1 < ls.count { return ls[i + 1].time }
        return max(player.duration > 0 ? player.duration : ls[i].time + 6, ls[i].time + 4)
    }

    private func backgroundLayer(_ size: CGSize) -> some View {
        blurredCoverBackground(url: APIClient.coverURL(player.current?.cover), size: size)
    }

    private func shadeLayer(_ size: CGSize) -> some View {
        LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.75)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height)
    }

    private var topBar: some View {
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
        return HStack(spacing: 0) {
            Button {
                dismissLyricsToPortrait { dismiss() }
            } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.top, safeTop + 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - 跳动歌词（Folia 默认逐字弹跳卡拉OK 风）
/// 视觉：当前句居中大字，逐字按时间戳「弹性弹入」（缩放 0.4→1 + 上跳 + 过冲回弹），
/// 已唱字亮白、未到字不可见；上一句/下一句在两侧淡出缩小。无整句坠落（区别于 miSide 立体掉落）。
struct BounceLyricsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var tick: Double = 0
    @State private var tickTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { player.lyrics }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                backgroundLayer(geo.size)
                shadeLayer(geo.size)
                stage(geo)
                topBar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { tick = player.currentTime; activeIndex = findIndex(tick); setLyricsLandscape(true); setLyricsIdle(true) }
        .onReceive(tickTimer) { _ in
            let nt = player.currentTime
            guard abs(nt - tick) > 0.02 else { return }
            tick = nt
            drive()
        }
        .onDisappear { setLyricsLandscape(false); setLyricsIdle(false) }
    }

    private func stage(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 22) {
            if activeIndex - 1 >= 0, activeIndex - 1 < lines.count {
                lineText(lines[activeIndex - 1], emphasized: false)
                    .opacity(0.32)
                    .scaleEffect(0.82)
            }
            if activeIndex >= 0, activeIndex < lines.count {
                currentLine(lines[activeIndex])
            }
            if activeIndex + 1 < lines.count {
                lineText(lines[activeIndex + 1], emphasized: false)
                    .opacity(0.2)
                    .scaleEffect(0.82)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 30)
        .id(activeIndex)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: activeIndex)
    }

    private func currentLine(_ line: LyricLine) -> some View {
        BounceLine(line: line, words: effectiveWords(for: line), tick: tick)
    }

    // 没有逐字时间轴(yrc)的句子，按字符拆开并沿本句时长均匀分配时间，
    // 复用逐字弹跳管线，使“单独文字”也有逐字蹦出的效果（与有翻译/有 yrc 的歌一致）
    private func effectiveWords(for line: LyricLine) -> [LyricWord] {
        if !line.words.isEmpty { return line.words }
        let chars = Array(line.text)
        guard !chars.isEmpty else { return [] }
        let start = line.time
        let end: Double
        if activeIndex + 1 < lines.count {
            end = lines[activeIndex + 1].time
        } else {
            end = max(player.duration > 0 ? player.duration : line.time + 6, line.time + 4)
        }
        let span = max(end - start, 0.5)
        let per = span / Double(chars.count)
        return chars.enumerated().map { i, c in
            LyricWord(time: start + per * Double(i), duration: per, text: String(c))
        }
    }

    private func lineText(_ line: LyricLine, emphasized: Bool) -> some View {
        Group {
            if line.words.isEmpty {
                Text(line.text.isEmpty ? "·" : line.text)
            } else {
                Text(line.words.map { $0.text }.joined())
            }
        }
        .font(.system(size: emphasized ? 30 : 24, weight: emphasized ? .bold : .semibold))
        .foregroundColor(.white)
        .lineLimit(nil)
        .minimumScaleFactor(1.0)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
    }

    // 当前句整体：每切到这一句时用弹簧「跳」入（保证即使无逐字数据也明显跳动）
    private struct BounceLine: View {
        let line: LyricLine
        let words: [LyricWord]
        let tick: Double
        @State private var entered = false
        var body: some View {
            VStack(spacing: 10) {
                if words.isEmpty {
                    Text(line.text.isEmpty ? "·" : line.text)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(nil)
                        .minimumScaleFactor(1.0)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                } else {
                    BounceFlow {
                        // 用索引而非 LyricWord 的 UUID 作 ForEach 标识：
                        // 合成逐字数组每 0.1s 刷新都会生成新 UUID，若按 UUID 标识会被反复销毁重建导致闪烁；
                        // 按索引则身份稳定，动画只在入场时触发一次
                        ForEach(0..<words.count, id: \.self) { idx in
                            BounceWord(text: words[idx].text, appeared: tick >= words[idx].time)
                        }
                    }
                    .font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !line.translation.isEmpty {
                    Text(line.translation)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(nil)
                        .minimumScaleFactor(1.0)
                        .multilineTextAlignment(.leading)
                }
            }
            .scaleEffect(entered ? 1 : 0.74)
            .offset(y: entered ? 0 : 36)
            .opacity(entered ? 1 : 0)
            .blur(radius: entered ? 0 : 8)
            .animation(.interpolatingSpring(stiffness: 280, damping: 17), value: entered)
            .onAppear { DispatchQueue.main.async { entered = true } }
        }
    }

    // 逐字弹跳单元：到达其时间时弹性弹入（叠加在整句跳动之上）
    private struct BounceWord: View {
        let text: String
        let appeared: Bool
        @State private var shown = false
        var body: some View {
            Text(text)
                .scaleEffect(shown ? 1 : 0.3)
                .offset(y: shown ? 0 : 16)
                .opacity(shown ? 1 : 0)
                .blur(radius: shown ? 0 : 4)
                .animation(.interpolatingSpring(stiffness: 380, damping: 14), value: shown)
                .onChange(of: appeared) { if $0 { shown = true } }
                .onAppear { if appeared { shown = true } }
        }
    }

    // 逐字流式布局（自动换行），子视图自行负责弹跳 transform（基于槽位，不挤占布局）
    private struct BounceFlow: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxW = proposal.width ?? .infinity
            let spacing: CGFloat = 3
            var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, totalH: CGFloat = 0
            for s in subviews {
                let sz = s.sizeThatFits(.unspecified)
                if x + sz.width > maxW, x > 0 { y += lineH; x = 0; lineH = 0 }
                x += sz.width + spacing
                lineH = max(lineH, sz.height)
                totalH = max(totalH, y + lineH)
            }
            return CGSize(width: min(maxW, max(x - spacing, 0)), height: totalH)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let spacing: CGFloat = 3
            var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
            for s in subviews {
                let sz = s.sizeThatFits(.unspecified)
                if x + sz.width > bounds.width, x > 0 { y += lineH; x = 0; lineH = 0 }
                s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
                x += sz.width + spacing
                lineH = max(lineH, sz.height)
            }
        }
    }

    private func drive() {
        let ls = lines
        guard !ls.isEmpty else { activeIndex = -1; return }
        let cur = findIndex(tick)
        if cur != activeIndex { activeIndex = cur }
    }
    private func findIndex(_ t: Double) -> Int {
        let ls = lines
        guard !ls.isEmpty else { return -1 }
        var lo = 0, hi = ls.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ls[mid].time <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    private func backgroundLayer(_ size: CGSize) -> some View {
        blurredCoverBackground(url: APIClient.coverURL(player.current?.cover), size: size)
    }
    private func shadeLayer(_ size: CGSize) -> some View {
        LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.75)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height)
    }
    private var topBar: some View {
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
        return HStack(spacing: 0) {
            Button {
                dismissLyricsToPortrait { dismiss() }
            } label: {
                KXIcon(icon: .chevronDown, size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.top, safeTop + 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - 歌曲信息 / 音质 / 加入网易云歌单
struct SongInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
    let song: Song?
    @State private var quality: String = "检测中…"
    @State private var commentCount: Int?
    @State private var addingPID: String?
    @State private var addNotice: String?
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var creatingPlaylist = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    infoRow("标题", song?.title ?? "—")
                    infoRow("艺术家", song?.artist ?? "—")
                    infoRow("专辑", (song?.album ?? "").isEmpty ? "—" : (song?.album ?? "—"))
                    infoRow("时长", song.map { fmtDuration($0.duration) } ?? "—")
                    infoRow("网易云 ID", song?.ncmID ?? "—")
                } header: {
                    Text("歌曲")
                }

                Section {
                    HStack {
                        Text("当前音质档位").font(.footnote)
                        Spacer()
                        Text(APIClient.audioQualityName).font(.caption).foregroundColor(.kxAccent)
                    }
                    HStack {
                        Text("上游实际音质").font(.footnote)
                        Spacer()
                        Text(quality).font(.caption).foregroundColor(.secondary)
                    }
                    if let c = commentCount {
                        infoRow("评论数", "\(c) 条")
                    }
                } header: {
                    Text("播放")
                } footer: {
                    Text("档位在「设置」里切换，下一首生效；VIP 歌曲上游只返回 128 kbps 试听片段。")
                        .font(.caption2)
                }

                Section {
                    if auth.ncmBound {
                        Button {
                            newPlaylistName = ""
                            showCreatePlaylist = true
                        } label: {
                            HStack(spacing: 10) {
                                KXIcon(icon: .plusCircle, size: 17, color: .kxAccent)
                                Text("新建网易云歌单")
                                    .font(.subheadline).foregroundColor(.primary)
                                Spacer()
                                if creatingPlaylist { ProgressView().scaleEffect(0.7) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(creatingPlaylist)
                        .alert("新建网易云歌单", isPresented: $showCreatePlaylist) {
                            TextField("歌单名称", text: $newPlaylistName)
                            Button("取消", role: .cancel) { newPlaylistName = "" }
                            Button("仅创建") {
                                Task { await createPlaylist(addCurrentSong: false) }
                            }
                            Button("创建并加入这首歌") {
                                Task { await createPlaylist(addCurrentSong: true) }
                            }
                        } message: {
                            Text("会在已绑定的网易云账号里真实创建歌单；选「创建并加入这首歌」会再写入当前歌曲。")
                        }
                    }
                    if !auth.ncmBound {
                        Text("绑定网易云账号后，可把这首歌加入云端歌单。")
                            .font(.caption).foregroundColor(.secondary)
                    } else if auth.ncmPlaylists.isEmpty {
                        Text("还没有云端歌单，点上方「新建网易云歌单」创建第一个。")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(auth.ncmPlaylists) { pl in
                            Button {
                                Task { await addToPlaylist(pl) }
                            } label: {
                                HStack(spacing: 10) {
                                    KXIcon(icon: .list, size: 17, color: .kxAccent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name).font(.subheadline).lineLimit(1)
                                        Text("\(pl.trackCount) 首")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if addingPID == pl.id {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Text("加入").font(.caption).foregroundColor(.kxAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("加入歌单")
                } footer: {
                    Text("会真实写入你的网易云账号，在网易云 App 里也能看到。")
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
            .alert("加入歌单", isPresented: Binding<Bool>(
                get: { addNotice != nil },
                set: { if !$0 { addNotice = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text(addNotice ?? "")
            }
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
        if auth.ncmBound { await auth.loadNCMPlaylists() }
        guard let id = song?.ncmID, !id.isEmpty else { quality = "本地曲目"; return }
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

    @MainActor
    private func addToPlaylist(_ pl: NCMPlaylist) async {
        guard let id = song?.ncmID else {
            addNotice = "这首歌没有网易云 ID，无法加入云端歌单"
            return
        }
        addingPID = pl.id
        do {
            try await APIClient.ncmAddToPlaylist(pid: pl.id, songID: id)
            addNotice = "已加入「\(pl.name)」"
        } catch {
            addNotice = "加入失败：\(error.localizedDescription)"
        }
        addingPID = nil
    }

    /// 在「加入歌单」模块内直接新建云端歌单，不用来回跳个人中心。
    /// 创建成功会刷新 auth.ncmPlaylists；选「创建并加入」时再写入当前歌曲。
    @MainActor
    private func createPlaylist(addCurrentSong: Bool) async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, !creatingPlaylist else { return }
        guard auth.ncmBound else {
            addNotice = "请先扫码绑定网易云账号"
            return
        }
        creatingPlaylist = true
        do {
            let pid = try await APIClient.ncmCreatePlaylist(name: name)
            await auth.loadNCMPlaylists()
            if addCurrentSong {
                if let id = song?.ncmID, !pid.isEmpty {
                    do {
                        try await APIClient.ncmAddToPlaylist(pid: pid, songID: id)
                        await auth.loadNCMPlaylists()
                        addNotice = "已创建「\(name)」并加入这首歌"
                    } catch {
                        addNotice = "歌单「\(name)」已创建，但加入歌曲失败：\(error.localizedDescription)"
                    }
                } else {
                    addNotice = "歌单「\(name)」已创建，但这首歌没有网易云 ID，无法自动加入"
                }
            } else {
                addNotice = "已创建歌单「\(name)」，点列表中的「加入」可添加这首歌"
            }
        } catch {
            addNotice = "创建失败：\(error.localizedDescription)"
        }
        creatingPlaylist = false
    }
}

// MARK: - 旋转专辑封面（独立子视图）
/// 平滑化：角度按真实经过时间 dt 累计（accumulated += degPerSec * dt），60fps 定时器；
/// 暂停时冻结；去掉 .compositingGroup()，由 GPU 直接整层变换，消除逐帧重栅格化的微闪。
private struct RotatingAlbumCover: View {
    let url: URL?
    let isPlaying: Bool
    private let rotationSeconds: Double = 20           // 一圈约 20 秒
    private var degPerSec: Double { 360 / rotationSeconds }

    @State private var accumulated: Double = 0
    @State private var last: Date = Date()
    @State private var ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.07)).frame(width: 300, height: 300)
            albumImage
                .frame(width: 266, height: 266)
                .rotationEffect(.degrees(accumulated))
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: 286, height: 286)
        }
        .onReceive(ticker) { now in
            let dt = now.timeIntervalSince(last)
            last = now
            guard isPlaying else { return }
            accumulated += degPerSec * dt
            if accumulated >= 360 { accumulated -= 360 }
        }
    }

    @ViewBuilder
    private var albumImage: some View {
        AsyncImage(url: url) { phase in
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
    }
}
