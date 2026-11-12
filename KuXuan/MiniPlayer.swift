import SwiftUI

/// 底部迷你播放条（Apple Music 风格）。
///
/// 布局：外层毛玻璃背景一直铺到屏幕物理底边（RootView 忽略底部安全区），
/// 内层是一张左右留 8pt 的圆角材质卡片，控件靠 bottomInset 抬离 home indicator。
/// 这样既「贴在最下面」，又保留苹果那种悬浮卡片质感。
///
/// 进度：卡片顶沿的细线绑定 currentTime / duration（引擎每 0.5s 推送），可拖动 seek。
struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerEngine
    /// 底部安全区高度，由外层 GeometryReader 传入
    var bottomInset: CGFloat = 0

    @State private var dragFraction: CGFloat?

    private var progress: CGFloat {
        let d = player.duration
        guard d.isFinite, d > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / d, 0), 1))
    }
    /// 拖动过程中优先显示手指位置，松手后回到真实进度
    private var shown: CGFloat { dragFraction ?? progress }

    var body: some View {
        card
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 6 + bottomInset)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                    }
            )
    }

    // MARK: 圆角材质卡片
    private var card: some View {
        VStack(spacing: 0) {
            progressStrip
            contentRow
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.09), radius: 10, y: 3)
    }

    // MARK: 真实进度条（2.5pt 轨道 + 已播放部分，10pt 高的拖动热区）
    private var progressStrip: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: geo.size.width, height: 2.5)
                Rectangle()
                    .fill(LinearGradient.kx)
                    .frame(width: max(0, geo.size.width * shown), height: 2.5)
                    .animation(.linear(duration: 0.45), value: progress)
            }
            .frame(width: geo.size.width, height: 10, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragFraction = Self.fraction(v.location.x, width: geo.size.width)
                    }
                    .onEnded { v in
                        let f = Self.fraction(v.location.x, width: geo.size.width)
                        if player.duration.isFinite, player.duration > 0 {
                            player.seek(to: Double(f) * player.duration)
                        }
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 10)
    }

    private static func fraction(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x / max(width, 1), 0), 1)
    }

    // MARK: 控件行
    private var contentRow: some View {
        HStack(spacing: 11) {
            Button { player.showFullPlayer = true } label: {
                KXCover(url: APIClient.coverURL(player.current?.cover, size: 120))
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.13), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            Button { player.showFullPlayer = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "未在播放")
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(player.current?.artist ?? "—")
                        .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 9)
    }
}
