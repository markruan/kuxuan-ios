import SwiftUI
import Foundation
import UIKit

// MARK: - 新感官 NEW SENSE · 原生设计系统
// 与 web/style.css 的 :root token 一一对应，便于 Web / 原生双端视觉统一。
// 品牌渐变 135°: #FFB489 → #F5788F → #B3315F；强调色 #D6487A；
// 圆角 10/14/18/24/30；卡片用系统自适应表面色 + 柔阴影（暗色模式自动适配）。

extension Color {
    /// 由十六进制构造颜色（如 0xFFAA85）
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    // 品牌三色
    static let kxBrand1 = Color(hex: 0xFFAA85)
    static let kxBrand2 = Color(hex: 0xB3315F)
    static let kxBrand3 = Color(hex: 0x7A2A6B)
    // 强调色（浅色 #D6487A）
    static let kxAccent = Color(hex: 0xD6487A)
    // 语义文字（浅色默认；深色由系统色在各 View 兜底）
    static let kxText2 = Color(hex: 0x6A5D66)
    static let kxText3 = Color(hex: 0x9C8F98)
}

extension LinearGradient {
    /// 主品牌渐变：#FFB489 → #F5788F → #B3315F（135°）
    static var kx: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFB489), Color(hex: 0xF5788F), Color(hex: 0xB3315F)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 柔和品牌渐变（背景晕染，低透明度）
    static var kxSoft: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFAA85, opacity: 0.18), Color(hex: 0xB3315F, opacity: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 圆角尺度（对应 CSS --r-xs..--r-xl）
enum KXRadius {
    static let xs: CGFloat = 10
    static let sm: CGFloat = 14
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let xl: CGFloat = 30
    static let pill: CGFloat = 999
    /// 列表内封面 / 缩略图圆角（40–46pt 方形封面的统一取值）
    static let cover: CGFloat = 8
}

// MARK: - 卡片修饰（圆角 + 柔阴影 + 系统自适应表面色）
struct KXCardModifier: ViewModifier {
    var radius: CGFloat
    var shadowRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: shadowRadius, x: 0, y: 2)
            )
    }
}

extension View {
    /// 新感官卡片：圆角 + 柔阴影 + 系统自适应表面
    func kxCard(radius: CGFloat = KXRadius.sm, shadowRadius: CGFloat = 8) -> some View {
        self.modifier(KXCardModifier(radius: radius, shadowRadius: shadowRadius))
    }
}

/// 只有异常 / 需要用户决策的文案才允许用 toast / alert 打断操作。
/// 「已收藏」「已创建」「评论已发布」这类成功反馈，界面状态本身已经表达，
/// 再弹一条属于对用户无用的提醒。
func KXNeedsAttention(_ s: String) -> Bool {
    let keys = ["失败", "还原", "未连接", "未绑定", "无法", "请先", "不支持", "不能"]
    return keys.contains { s.contains($0) }
}

// MARK: - 收藏云同步短提示
struct FavSyncToast: View {
    @EnvironmentObject var player: PlayerEngine
    private var message: String? {
        let m = player.favArtistNotice ?? player.favNotice
        guard let m, KXNeedsAttention(m) else { return nil }
        return m
    }
    var body: some View {
        Group {
            if let msg = message {
                HStack(spacing: 7) {
                    KXIcon(icon: msg.contains("失败") ? .warning : .cloudCheck,
                           size: 15, color: .white)
                    Text(msg).font(.caption).lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.black.opacity(0.78), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                // 合并为一个无障碍元素，VoiceOver 读到完整句子而不是图标+碎片文本
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message)
        // 纯视觉 toast 对 VoiceOver 用户等于不存在：出现时主动播报一次
        .onChange(of: message) { new in
            if let new { KXAnnounce(new) }
        }
    }
}

/// 播放失败提示（版权/网络受限/上游 451）：由 PlayerEngine 自动跳过不可播放歌曲后给出，
/// 约 2.8s 自动消失。橙色高亮区别于收藏提示，挂在全屏播放页顶部。
struct PlayErrorToast: View {
    @EnvironmentObject var player: PlayerEngine
    var body: some View {
        Group {
            if let msg = player.playError {
                HStack(spacing: 7) {
                    KXIcon(icon: .warning, size: 15, color: .white)
                    Text(msg).font(.caption).lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.orange.opacity(0.92), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                // 橙色只用来区分提示类型，文字「无法播放」已表达语义，不单靠颜色传达信息
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.playError)
        .onChange(of: player.playError) { new in
            if let new { KXAnnounce(new) }
        }
    }
}

// MARK: - KuXuan 统一图标体系（自绘 Path，不使用 SF Symbols）
// 设计约束：所有图标统一 24×24 网格、1.9 线宽、圆角端点/拐角、品牌强调色。
// 目的：个人中心 / 设置 / 扫码 / 收藏等页面不再混用苹果系统图标，视觉语言一致。
enum KXIconName {
    case menu, search, close, person, heart, heartFill, clock, history,
         checkCircle, check, qr, unlink, gear, sync, server, note,
         network, wifi, list, wave, chevron, chevronDown, chevronLeft, lyric,
         refresh, download, warning, cloudCheck,
         play, pause, back, forward,
         repeatAll, repeatOne, shuffle, comment, more, flame, thumb,
         plusCircle, send, reply, expand
}

private func KXP(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func kxAddHeart(_ p: inout Path) {
    p.move(to: KXP(12, 20.5))
    p.addCurve(to: KXP(4.2, 12.8), control1: KXP(9.0, 18.0), control2: KXP(4.2, 15.8))
    p.addCurve(to: KXP(7.0, 6.2),  control1: KXP(4.2, 9.6),  control2: KXP(5.0, 6.2))
    p.addCurve(to: KXP(12, 8.8),   control1: KXP(8.6, 6.2),  control2: KXP(10.6, 7.0))
    p.addCurve(to: KXP(17.0, 6.2), control1: KXP(13.4, 7.0), control2: KXP(15.4, 6.2))
    p.addCurve(to: KXP(19.8, 12.8), control1: KXP(19.0, 6.2), control2: KXP(19.8, 9.6))
    p.addCurve(to: KXP(12, 20.5), control1: KXP(19.8, 15.8), control2: KXP(15.0, 18.0))
    p.closeSubpath()
}

struct KXIconShape: Shape {
    let icon: KXIconName

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        switch icon {
        case .menu:
            p.move(to: KXP(4, 7)); p.addLine(to: KXP(20, 7))
            p.move(to: KXP(4, 12)); p.addLine(to: KXP(20, 12))
            p.move(to: KXP(4, 17)); p.addLine(to: KXP(20, 17))
        case .search:
            p.addEllipse(in: CGRect(x: 3.8, y: 3.8, width: 12.4, height: 12.4))
            p.move(to: KXP(15.3, 15.3)); p.addLine(to: KXP(20.2, 20.2))
        case .close:
            p.addEllipse(in: CGRect(x: 3.2, y: 3.2, width: 17.6, height: 17.6))
            p.move(to: KXP(9, 9)); p.addLine(to: KXP(15, 15))
            p.move(to: KXP(15, 9)); p.addLine(to: KXP(9, 15))
        case .person:
            p.addEllipse(in: CGRect(x: 8.3, y: 3.8, width: 7.4, height: 7.4))
            p.move(to: KXP(4.5, 20))
            p.addQuadCurve(to: KXP(19.5, 20), control: KXP(12, 12.5))
        case .heart, .heartFill:
            kxAddHeart(&p)
        case .clock:
            p.addEllipse(in: CGRect(x: 3.4, y: 3.4, width: 17.2, height: 17.2))
            p.move(to: KXP(12, 6.8)); p.addLine(to: KXP(12, 12)); p.addLine(to: KXP(16, 14.3))
        case .history:
            p.move(to: KXP(4, 7)); p.addLine(to: KXP(4, 4)); p.addLine(to: KXP(7.5, 4))
            p.move(to: KXP(4.2, 11))
            p.addCurve(to: KXP(12, 4.5), control1: KXP(4.2, 7.6), control2: KXP(7.6, 4.5))
            p.addCurve(to: KXP(19.8, 12), control1: KXP(16.4, 4.5), control2: KXP(19.8, 7.6))
            p.addCurve(to: KXP(12, 19.5), control1: KXP(19.8, 16.4), control2: KXP(16.4, 19.5))
            p.move(to: KXP(12, 7.5)); p.addLine(to: KXP(12, 12)); p.addLine(to: KXP(15.5, 13.5))
        case .checkCircle:
            p.addEllipse(in: CGRect(x: 3.2, y: 3.2, width: 17.6, height: 17.6))
            p.move(to: KXP(8, 12.2)); p.addLine(to: KXP(11, 15.2)); p.addLine(to: KXP(16.4, 9))
        case .check:
            p.move(to: KXP(4.5, 12.5)); p.addLine(to: KXP(9.5, 17.5)); p.addLine(to: KXP(19.5, 6.5))
        case .qr:
            p.addRect(CGRect(x: 3.2, y: 3.2, width: 7.2, height: 7.2))
            p.addRect(CGRect(x: 5.4, y: 5.4, width: 2.8, height: 2.8))
            p.addRect(CGRect(x: 13.6, y: 3.2, width: 7.2, height: 7.2))
            p.addRect(CGRect(x: 15.8, y: 5.4, width: 2.8, height: 2.8))
            p.addRect(CGRect(x: 3.2, y: 13.6, width: 7.2, height: 7.2))
            p.addRect(CGRect(x: 5.4, y: 15.8, width: 2.8, height: 2.8))
            p.addRect(CGRect(x: 13.6, y: 13.6, width: 2.6, height: 2.6))
            p.addRect(CGRect(x: 18.2, y: 13.6, width: 2.6, height: 2.6))
            p.addRect(CGRect(x: 13.6, y: 18.2, width: 2.6, height: 2.6))
            p.addRect(CGRect(x: 18.2, y: 18.2, width: 2.6, height: 2.6))
        case .unlink:
            p.move(to: KXP(13.5, 4)); p.addLine(to: KXP(5, 4))
            p.addLine(to: KXP(5, 20)); p.addLine(to: KXP(13.5, 20))
            p.move(to: KXP(10, 12)); p.addLine(to: KXP(20, 12))
            p.move(to: KXP(17, 9)); p.addLine(to: KXP(20, 12)); p.addLine(to: KXP(17, 15))
        case .gear:
            for i in 0..<16 {
                let a = Double(i) * 2 * Double.pi / 16.0 - Double.pi / 2
                let r: CGFloat = (i % 2 == 0) ? 9.6 : 7.3
                let x = 12 + CGFloat(cos(a)) * r
                let y = 12 + CGFloat(sin(a)) * r
                if i == 0 { p.move(to: KXP(x, y)) } else { p.addLine(to: KXP(x, y)) }
            }
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 9.4, y: 9.4, width: 5.2, height: 5.2))
        case .sync:
            p.move(to: KXP(4.5, 10.5))
            p.addCurve(to: KXP(19.5, 10.5), control1: KXP(4.5, 4), control2: KXP(19.5, 4))
            p.move(to: KXP(19.5, 13.5))
            p.addCurve(to: KXP(4.5, 13.5), control1: KXP(19.5, 20), control2: KXP(4.5, 20))
            p.move(to: KXP(2.2, 7.8)); p.addLine(to: KXP(4.5, 10.5)); p.addLine(to: KXP(7.5, 7.8))
            p.move(to: KXP(16.5, 16.2)); p.addLine(to: KXP(19.5, 13.5)); p.addLine(to: KXP(21.8, 16.2))
        case .server:
            p.addRoundedRect(in: CGRect(x: 3.2, y: 3.8, width: 17.6, height: 7),
                             cornerSize: CGSize(width: 1.6, height: 1.6))
            p.addRoundedRect(in: CGRect(x: 3.2, y: 13.2, width: 17.6, height: 7),
                             cornerSize: CGSize(width: 1.6, height: 1.6))
            p.addEllipse(in: CGRect(x: 5.8, y: 6.2, width: 2.2, height: 2.2))
            p.addEllipse(in: CGRect(x: 5.8, y: 15.6, width: 2.2, height: 2.2))
            p.move(to: KXP(10, 7.3)); p.addLine(to: KXP(17.6, 7.3))
            p.move(to: KXP(10, 16.7)); p.addLine(to: KXP(17.6, 16.7))
        case .note:
            p.move(to: KXP(11.8, 17)); p.addLine(to: KXP(11.8, 5.8))
            p.addLine(to: KXP(19.2, 4.2)); p.addLine(to: KXP(19.2, 7.4))
            p.addLine(to: KXP(11.8, 9))
            p.addEllipse(in: CGRect(x: 5.6, y: 14.8, width: 6.6, height: 4.6))
        case .network:
            p.addEllipse(in: CGRect(x: 9, y: 2.6, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 2.4, y: 15, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 15.6, y: 15, width: 6, height: 6))
            p.move(to: KXP(12, 8.6)); p.addLine(to: KXP(5.4, 15))
            p.move(to: KXP(12, 8.6)); p.addLine(to: KXP(18.6, 15))
        case .wifi:
            p.move(to: KXP(3, 10)); p.addQuadCurve(to: KXP(21, 10), control: KXP(12, 2.5))
            p.move(to: KXP(6.2, 14)); p.addQuadCurve(to: KXP(17.8, 14), control: KXP(12, 8))
            p.addEllipse(in: CGRect(x: 10.6, y: 17.4, width: 2.8, height: 2.8))
        case .list:
            p.move(to: KXP(8.5, 6)); p.addLine(to: KXP(20, 6))
            p.move(to: KXP(8.5, 12)); p.addLine(to: KXP(20, 12))
            p.move(to: KXP(8.5, 18)); p.addLine(to: KXP(20, 18))
            p.addEllipse(in: CGRect(x: 3, y: 4.6, width: 2.8, height: 2.8))
            p.addEllipse(in: CGRect(x: 3, y: 10.6, width: 2.8, height: 2.8))
            p.addEllipse(in: CGRect(x: 3, y: 16.6, width: 2.8, height: 2.8))
        case .wave:
            p.move(to: KXP(5, 10)); p.addLine(to: KXP(5, 14))
            p.move(to: KXP(9.5, 6)); p.addLine(to: KXP(9.5, 18))
            p.move(to: KXP(14.5, 8)); p.addLine(to: KXP(14.5, 16))
            p.move(to: KXP(19, 11)); p.addLine(to: KXP(19, 13))
        case .chevron:
            p.move(to: KXP(9, 5)); p.addLine(to: KXP(16, 12)); p.addLine(to: KXP(9, 19))
        case .chevronLeft:
            p.move(to: KXP(15, 5)); p.addLine(to: KXP(8, 12)); p.addLine(to: KXP(15, 19))
        case .refresh:
            p.move(to: KXP(19.5, 9))
            p.addCurve(to: KXP(18.5, 17.2), control1: KXP(21.2, 12.5), control2: KXP(20.5, 15.6))
            p.addCurve(to: KXP(6.2, 18.5), control1: KXP(15.5, 20.2), control2: KXP(9.3, 20.2))
            p.addCurve(to: KXP(4.2, 10.5), control1: KXP(3.2, 16.5), control2: KXP(3.2, 12.8))
            p.move(to: KXP(4.2, 4.8)); p.addLine(to: KXP(4.2, 10.5)); p.addLine(to: KXP(9.6, 10.5))
        case .download:
            p.move(to: KXP(12, 3)); p.addLine(to: KXP(12, 15))
            p.move(to: KXP(8, 11)); p.addLine(to: KXP(12, 15)); p.addLine(to: KXP(16, 11))
            p.move(to: KXP(4, 17.5)); p.addLine(to: KXP(4, 20))
            p.addLine(to: KXP(20, 20)); p.addLine(to: KXP(20, 17.5))
        case .warning:
            p.move(to: KXP(12, 3)); p.addLine(to: KXP(21.5, 20))
            p.addLine(to: KXP(2.5, 20)); p.closeSubpath()
            p.move(to: KXP(12, 9)); p.addLine(to: KXP(12, 14.5))
            p.addEllipse(in: CGRect(x: 11, y: 16.6, width: 2, height: 2))
        case .cloudCheck:
            p.move(to: KXP(6.5, 18.5))
            p.addCurve(to: KXP(6.5, 11.5), control1: KXP(3.2, 18.5), control2: KXP(3.2, 11.5))
            p.addCurve(to: KXP(13.5, 9), control1: KXP(7.8, 8), control2: KXP(10.5, 9))
            p.addCurve(to: KXP(18, 18.5), control1: KXP(17.5, 9), control2: KXP(20.8, 13.5))
            p.move(to: KXP(9.2, 15.2)); p.addLine(to: KXP(11.6, 17.4)); p.addLine(to: KXP(16, 13))
        case .play:
            p.move(to: KXP(8, 4.5)); p.addLine(to: KXP(19, 12))
            p.addLine(to: KXP(8, 19.5)); p.closeSubpath()
        case .plusCircle:
            p.addEllipse(in: CGRect(x: 3.2, y: 3.2, width: 17.6, height: 17.6))
            p.move(to: KXP(12, 8)); p.addLine(to: KXP(12, 16))
            p.move(to: KXP(8, 12)); p.addLine(to: KXP(16, 12))
        case .chevronDown:
            p.move(to: KXP(5, 9)); p.addLine(to: KXP(12, 16)); p.addLine(to: KXP(19, 9))
        case .lyric:
            p.move(to: KXP(4, 5)); p.addLine(to: KXP(20, 5))
            p.move(to: KXP(4, 10)); p.addLine(to: KXP(16, 10))
            p.move(to: KXP(4, 15)); p.addLine(to: KXP(20, 15))
            p.move(to: KXP(4, 20)); p.addLine(to: KXP(13, 20))
        case .pause:
            p.addRect(CGRect(x: 6, y: 4.5, width: 4, height: 15))
            p.addRect(CGRect(x: 14, y: 4.5, width: 4, height: 15))
        case .back:
            p.move(to: KXP(19, 5)); p.addLine(to: KXP(8, 12))
            p.addLine(to: KXP(19, 19)); p.closeSubpath()
            p.move(to: KXP(5, 5)); p.addLine(to: KXP(5, 19))
        case .forward:
            p.move(to: KXP(5, 5)); p.addLine(to: KXP(16, 12))
            p.addLine(to: KXP(5, 19)); p.closeSubpath()
            p.move(to: KXP(19, 5)); p.addLine(to: KXP(19, 19))
        case .repeatAll:
            p.move(to: KXP(4, 10)); p.addLine(to: KXP(4, 7)); p.addLine(to: KXP(17, 7))
            p.move(to: KXP(14, 4)); p.addLine(to: KXP(17, 7)); p.addLine(to: KXP(14, 10))
            p.move(to: KXP(20, 14)); p.addLine(to: KXP(20, 17)); p.addLine(to: KXP(7, 17))
            p.move(to: KXP(10, 14)); p.addLine(to: KXP(7, 17)); p.addLine(to: KXP(10, 20))
        case .repeatOne:
            p.move(to: KXP(4, 10)); p.addLine(to: KXP(4, 7)); p.addLine(to: KXP(17, 7))
            p.move(to: KXP(14, 4)); p.addLine(to: KXP(17, 7)); p.addLine(to: KXP(14, 10))
            p.move(to: KXP(20, 14)); p.addLine(to: KXP(20, 17)); p.addLine(to: KXP(7, 17))
            p.move(to: KXP(10, 14)); p.addLine(to: KXP(7, 17)); p.addLine(to: KXP(10, 20))
            p.move(to: KXP(11, 10.5)); p.addLine(to: KXP(13, 9.5))
            p.addLine(to: KXP(13, 14.5))
            p.move(to: KXP(11.5, 14.5)); p.addLine(to: KXP(14.5, 14.5))
        case .shuffle:
            p.move(to: KXP(3, 6)); p.addLine(to: KXP(6, 6))
            p.addCurve(to: KXP(17, 18), control1: KXP(11, 6), control2: KXP(11, 18))
            p.move(to: KXP(14, 15.5)); p.addLine(to: KXP(17, 18)); p.addLine(to: KXP(20, 15.5))
            p.move(to: KXP(3, 18)); p.addLine(to: KXP(6, 18))
            p.addCurve(to: KXP(17, 6), control1: KXP(11, 18), control2: KXP(11, 6))
            p.move(to: KXP(14, 8.5)); p.addLine(to: KXP(17, 6)); p.addLine(to: KXP(20, 8.5))
        case .comment:
            p.move(to: KXP(4, 5)); p.addLine(to: KXP(20, 5))
            p.addLine(to: KXP(20, 16)); p.addLine(to: KXP(10, 16))
            p.addLine(to: KXP(5, 20)); p.addLine(to: KXP(5, 16))
            p.addLine(to: KXP(4, 16)); p.closeSubpath()
            p.move(to: KXP(8, 10.5)); p.addLine(to: KXP(16, 10.5))
        case .more:
            p.addEllipse(in: CGRect(x: 3, y: 10.5, width: 3, height: 3))
            p.addEllipse(in: CGRect(x: 10.5, y: 10.5, width: 3, height: 3))
            p.addEllipse(in: CGRect(x: 18, y: 10.5, width: 3, height: 3))
        case .flame:
            p.move(to: KXP(12, 2.8))
            p.addCurve(to: KXP(19, 12), control1: KXP(17, 7), control2: KXP(19, 9.5))
            p.addCurve(to: KXP(12, 21), control1: KXP(19, 17), control2: KXP(16, 21))
            p.addCurve(to: KXP(5, 12), control1: KXP(8, 21), control2: KXP(5, 17))
            p.addCurve(to: KXP(12, 2.8), control1: KXP(5, 9.5), control2: KXP(7, 7))
            p.closeSubpath()
            p.move(to: KXP(12, 11))
            p.addCurve(to: KXP(14.5, 16), control1: KXP(14.5, 13.5), control2: KXP(14.5, 15))
            p.addCurve(to: KXP(12, 18), control1: KXP(14.5, 17.5), control2: KXP(13.3, 18))
            p.addCurve(to: KXP(9.5, 16), control1: KXP(10.7, 18), control2: KXP(9.5, 17.5))
            p.addCurve(to: KXP(12, 11), control1: KXP(9.5, 15), control2: KXP(9.5, 13.5))
        case .thumb:
            p.move(to: KXP(7, 10)); p.addLine(to: KXP(11, 10))
            p.addLine(to: KXP(13, 4)); p.addLine(to: KXP(16, 4))
            p.addLine(to: KXP(16, 10)); p.addLine(to: KXP(20, 10))
            p.addLine(to: KXP(20, 19)); p.addLine(to: KXP(7, 19)); p.closeSubpath()
            p.addRect(CGRect(x: 3, y: 10, width: 3, height: 9))
        case .send:
            p.move(to: KXP(21, 3)); p.addLine(to: KXP(3, 10.5))
            p.addLine(to: KXP(10.5, 13.5)); p.addLine(to: KXP(13, 21))
            p.addLine(to: KXP(21, 3)); p.closeSubpath()
            p.move(to: KXP(3, 10.5)); p.addLine(to: KXP(13, 21))
        case .reply:
            p.move(to: KXP(9.5, 5.5)); p.addLine(to: KXP(4, 11)); p.addLine(to: KXP(9.5, 16.5))
            p.move(to: KXP(4, 11)); p.addLine(to: KXP(14, 11))
            p.addCurve(to: KXP(20, 16), control1: KXP(20, 11), control2: KXP(20, 13.5))
        case .expand:
            // 四角外扩的全屏框
            let o: CGFloat = 4, e: CGFloat = 9, f: CGFloat = 15, g: CGFloat = 20
            p.move(to: KXP(o, e)); p.addLine(to: KXP(o, o)); p.addLine(to: KXP(e, o))
            p.move(to: KXP(f, o)); p.addLine(to: KXP(g, o)); p.addLine(to: KXP(g, e))
            p.move(to: KXP(o, f)); p.addLine(to: KXP(o, g)); p.addLine(to: KXP(e, g))
            p.move(to: KXP(f, g)); p.addLine(to: KXP(g, g)); p.addLine(to: KXP(g, f))
        }
        let tx = rect.minX + (rect.width - 24 * s) / 2
        let ty = rect.minY + (rect.height - 24 * s) / 2
        return p.applying(CGAffineTransform(scaleX: s, y: s))
            .applying(CGAffineTransform(translationX: tx, y: ty))
    }
}

/// 统一图标：默认品牌强调色 + 1.9 线性描边；filled=true 用于播放控制等主操作。
/// 图形全部来自 KXIconShape 自绘 Path，与苹果 SF Symbols 无关。
struct KXIcon: View {
    let icon: KXIconName
    var size: CGFloat = 20
    var color: Color = .kxAccent
    var filled: Bool = false

    var body: some View {
        Group {
            if filled || icon == .heartFill {
                KXIconShape(icon: icon).fill(color)
            } else {
                KXIconShape(icon: icon)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.9,
                                                      lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 列表行图标 + 文字，替代 Label(_, systemImage:)，保持整页图标风格一致。
/// 第一个参数刻意无标签，调用形如 KXLabel("设置", icon: .gear)。
struct KXLabel: View {
    let title: String
    let icon: KXIconName
    var color: Color = .kxAccent

    init(_ title: String, icon: KXIconName, color: Color = .kxAccent) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 11) {
            KXIcon(icon: icon, size: 19, color: color)
                .frame(width: 20, alignment: .center)
            Text(title)
        }
    }
}

/// 统一列表行：左图标 + 标题，右可选值。个人中心 / 设置等列表页共用，
/// 保证图标尺寸、配色、标题与值字号完全一致，避免不同页面各写一套行样式。
struct KXListRow: View {
    let icon: KXIconName
    let title: String
    var value: String? = nil
    var valueHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            KXIcon(icon: icon, size: 19, color: .kxAccent)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.body)
            Spacer()
            if let value {
                Text(value)
                    .font(.caption2)
                    .foregroundColor(valueHighlighted ? .kxAccent : .secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 统一返回按钮（替换系统原生 "< 返回"）
/// 在任意 push / sheet 子页链式调用 `.kxBackBar()` 即可：隐藏系统返回箭头，
/// 改用自绘的左 chevron（.chevronLeft），与「上一曲/下一曲」的 .back 箭头区分开，
/// 避免返回键看起来像跳上一曲。
struct KXBackButton: View {
    let label: String
    @Environment(\.dismiss) private var dismiss

    init(label: String = "") { self.label = label }

    var body: some View {
        Button { dismiss() } label: {
            HStack(spacing: 3) {
                KXIcon(icon: .chevronLeft, size: 20, color: .primary)
                    .frame(width: 22, height: 22)
                if !label.isEmpty {
                    Text(label).font(.body)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        // 自绘图标不产生文本、系统返回箭头又被隐藏，必须显式给 VoiceOver 标签，
        // 否则所有二级页的返回按钮只会被读成「按钮」。
        .accessibilityLabel(label.isEmpty ? "返回" : label)
        .accessibilityHint("返回上一页")
    }
}

extension View {
    /// 隐藏系统返回并以自定义 KXIcon(.back) 替换，统一全 App 返回样式。
    func kxBackBar(label: String = "") -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    KXBackButton(label: label)
                }
            }
    }
}

// MARK: - 无障碍 / 模态统一基础设施

/// 支持 Dynamic Type 的系统字号。
/// 项目里有 28 处 `.font(.system(size:))`：这类固定字号不随系统「更大字体」变化，
/// 大字模式下标题/按钮文字会被裁切。这里以指定文本样式为基准缩放，同时限制最大
/// 1.5 倍，避免辅助字号把逐字歌词画布与固定高度行撑破。
enum KXFont {
    static func scaled(_ size: CGFloat,
                       weight: Font.Weight = .regular,
                       relativeTo style: UIFont.TextStyle = .body,
                       maxScale: CGFloat = 1.5) -> Font {
        let raw = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        return .system(size: min(raw, size * maxScale), weight: weight)
    }
}

/// 统一纯图标按钮：自绘 KXIcon 本身不产生可朗读文本，必须在组件层补齐标签；
/// 同时把命中区钉到 HIG 要求的 44×44pt。
struct KXIconButton: View {
    let icon: KXIconName
    let label: String
    var hint: String? = nil
    var size: CGFloat = 20
    var color: Color = .white
    var filled: Bool = false
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KXIcon(icon: icon, size: size, color: color, filled: filled)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityHidden(true)   // 图标装饰，语义由按钮标签承担
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityValue(value ?? "")
    }
}

/// 统一模态关闭按钮：fullScreenCover 不自带系统关闭控件，歌手页 / 全屏歌词页共用这一枚，
/// 保证「有明确取消控件 + 一致的 VoiceOver 标签 + 44pt 命中区」。
struct KXModalCloseButton: View {
    var label: String = "关闭"
    var hint: String = "关闭当前页面"
    var color: Color = .white
    let action: () -> Void

    var body: some View {
        KXIconButton(icon: .chevronDown, label: label, hint: hint,
                     size: 22, color: color, action: action)
    }
}

/// 模态顶部的可拖动指示条：给 fullScreenCover / 自定义浮层一条**可发现**的下滑关闭路径。
/// 只挂在顶部 24pt 区域，避免与内容 ScrollView 的滚动手势竞争。
struct KXModalGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 20)
            .contentShape(Rectangle())
            .accessibilityHidden(true)      // VoiceOver 用显式关闭按钮，不占焦点
    }
}

/// 统一模态下滑关闭手势。绑定 isPresented，只有「垂直主导 + 下滑 > 90pt」才关闭；
/// 使用 simultaneousGesture，不阻塞子视图的滚动/按钮手势。
struct KXModalDismissGesture: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { v in
                    guard v.translation.height > 90,
                          v.translation.height > abs(v.translation.width) * 1.3 else { return }
                    if reduceMotion { isPresented = false }
                    else {
                        withAnimation(.easeInOut(duration: 0.25)) { isPresented = false }
                    }
                }
        )
    }
}

extension View {
    func kxModalDismiss(isPresented: Binding<Bool>) -> some View {
        self.modifier(KXModalDismissGesture(isPresented: isPresented))
    }
}

/// 无障碍播报：收藏同步 / 播放失败等短提示是纯视觉 toast，VoiceOver 用户完全感知不到。
/// 统一在提示出现时发一条 announcement（不打断当前焦点）。
func KXAnnounce(_ message: String) {
    guard UIAccessibility.isVoiceOverRunning, !message.isEmpty else { return }
    UIAccessibility.post(notification: .announcement, argument: message)
}

// MARK: - 骨架屏体系
// 每个页面用自己的骨架，形状/顺序/尺寸都对齐该页面的真实布局：
// 加载完成后只发生「灰色块变成内容」，不应该出现整页位置跳动或高度塌陷。
// 骨架一律钉死为视口宽度并左对齐（横向 ScrollView 除外），不给 VoiceOver 留一堆无意义元素。

/// 骨架基础块。所有骨架共用同一套填充色与圆角，避免各页灰度不一致。
struct KXSkelBar: View {
    var w: CGFloat
    var h: CGFloat
    var r: CGFloat = 4
    var body: some View {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .frame(width: w, height: h)
    }
}

private struct KXSkeletonChrome: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

extension View {
    func kxSkeletonChrome(_ label: String) -> some View {
        modifier(KXSkeletonChrome(label: label))
    }
}

/// 歌手页骨架：大封面 + 名 → 两枚胶囊按钮 → 简介 → 专辑横滑 → 相似歌手横滑 → 热门歌曲。
/// 旧的通用骨架只有「封面 + 5 行歌曲」，缺 4 个区块，数据回来时整页往下跳一大截。
struct KXArtistSkeleton: View {
    private let fill = Color(.secondarySystemFill)
    private var textW: CGFloat { max(160, UIScreen.main.bounds.width - 32) }
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    private func head(_ w: CGFloat) -> some View { bar(w, 18, 5) }
    private func songRow() -> some View {
        HStack(spacing: 12) {
            bar(46, 46, 6)
            VStack(alignment: .leading, spacing: 3) {
                bar(150, 13); bar(96, 10)
            }
            Spacer(minLength: 0)
        }
    }
    private func horizontalRow(cover: CGFloat, radius: CGFloat, count: Int,
                               gap: CGFloat, circle: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        if circle {
                            Circle().fill(fill).frame(width: cover, height: cover)
                        } else {
                            bar(cover, cover, radius)
                        }
                        bar(cover * 0.82, 9)
                    }
                    .frame(width: cover)
                }
            }
        }
        .frame(height: cover + 5 + 10)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // 头部：112 方形封面 + 歌手名 / 统计（与 ArtistDetailContent.header 一致）
                HStack(alignment: .top, spacing: 16) {
                    bar(112, 112, 12)
                    VStack(alignment: .leading, spacing: 6) {
                        bar(150, 20, 5)
                        bar(110, 12)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 112)
                    Spacer(minLength: 0)
                }
                // 收藏 / 播放全部 两枚 44pt 胶囊
                HStack(spacing: 12) {
                    Capsule().fill(fill).frame(width: 96, height: 44)
                    Capsule().fill(fill).frame(width: 110, height: 44)
                    Spacer(minLength: 0)
                }
                // 简介：标题 + 4 行正文 + 「展开全文」
                VStack(alignment: .leading, spacing: 8) {
                    head(88)
                    VStack(alignment: .leading, spacing: 6) {
                        bar(textW, 11)
                        bar(textW * 0.94, 11)
                        bar(textW * 0.98, 11)
                        bar(textW * 0.62, 11)
                        bar(60, 12)
                    }
                }
                // 专辑横滑 96pt 方形封面
                VStack(alignment: .leading, spacing: 10) {
                    head(48)
                    horizontalRow(cover: 96, radius: 8, count: 4, gap: 14, circle: false)
                }
                // 相似歌手横滑 74pt 圆形头像
                VStack(alignment: .leading, spacing: 10) {
                    head(80)
                    horizontalRow(cover: 74, radius: 0, count: 4, gap: 16, circle: true)
                }
                // 热门歌曲
                VStack(alignment: .leading, spacing: 8) {
                    head(100)
                    ForEach(0..<5, id: \.self) { _ in songRow() }
                }
                Spacer(minLength: 20)
            }
            .padding(.top, 6)
        }
        .scrollDisabled(true)
        .kxSkeletonChrome("正在加载歌手页")
    }
}

/// 歌单页骨架：居中 210 大封面 → 居中标题/统计 → 三枚并排按钮 → 分隔线 → 带序号歌曲行。
/// 旧通用骨架是左对齐 112 小封面，和真实页面形状完全不同。
struct KXPlaylistSkeleton: View {
    private let fill = Color(.secondarySystemFill)
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    private func songRow() -> some View {
        HStack(spacing: 12) {
            bar(16, 12).frame(width: 22)
            bar(46, 46, 6)
            VStack(alignment: .leading, spacing: 3) {
                bar(150, 13); bar(96, 10)
            }
            Spacer(minLength: 0)
            Circle().fill(fill).frame(width: 16, height: 16).frame(width: 44)
        }
        .padding(.vertical, 7)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 14) {
                    bar(210, 210, 12).frame(maxWidth: .infinity, alignment: .center)
                    VStack(spacing: 5) {
                        bar(160, 22, 5).frame(maxWidth: .infinity, alignment: .center)
                        bar(120, 12).frame(maxWidth: .infinity, alignment: .center)
                    }
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(fill)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

                Divider().padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        songRow()
                        Divider().padding(.leading, 76)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
        .scrollDisabled(true)
        .kxSkeletonChrome("正在加载歌单")
    }
}

/// 评论页骨架：insetGrouped 分组卡片 + 圆头像 + 名称/时间 + 两行正文 + 点赞行。
struct KXCommentSkeleton: View {
    private let fill = Color(.secondarySystemFill)
    private var textW: CGFloat { max(140, UIScreen.main.bounds.width - 120) }
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    private func commentRow() -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(fill).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    bar(70, 11)
                    Spacer(minLength: 0)
                    bar(44, 9)
                }
                bar(textW, 11)
                bar(textW * 0.72, 11)
                HStack { Spacer(minLength: 0); bar(40, 10) }
            }
        }
        .padding(.vertical, 4)
    }
    private func group(_ rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in commentRow() }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                bar(72, 13, 4).padding(.leading, 4)
                group(3)
                bar(110, 13, 4).padding(.leading, 4)
                group(5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDisabled(true)
        .kxSkeletonChrome("正在加载评论")
    }
}

/// 搜索页骨架：三种 tab 共用行结构，歌手 tab 为圆形头像、歌单 tab 带右侧箭头。
struct KXSearchSkeleton: View {
    /// 歌手结果用圆形头像，其余用方形封面
    var circular: Bool = false
    /// 歌单结果右侧有 chevron
    var chevron: Bool = false
    private let fill = Color(.secondarySystemFill)
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    private func resultRow() -> some View {
        HStack(spacing: 12) {
            if circular {
                Circle().fill(fill).frame(width: 44, height: 44)
            } else {
                bar(44, 44, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                bar(150, 13); bar(chevron ? 130 : 96, 10)
            }
            Spacer(minLength: 0)
            if chevron { bar(8, 12, 2) }
        }
        .padding(.vertical, 6)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<12, id: \.self) { _ in
                    resultRow()
                    Divider().padding(.leading, 56)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDisabled(true)
        .kxSkeletonChrome("正在加载搜索结果")
    }
}

/// 首页「每日推荐」局部骨架：section 标题 + 播放全部胶囊 + 110pt 横向卡片轨道。
/// 原来只有一个小转圈，加载时整块高度塌陷，数据回来会把下方内容顶下去。
struct KXDailySkeleton: View {
    private let fill = Color(.secondarySystemFill)
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                bar(88, 18, 5)
                Spacer(minLength: 0)
                Capsule().fill(fill).frame(width: 82, height: 26)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            bar(110, 110, 10)
                            bar(90, 10)
                            bar(60, 9)
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 164)
        }
        .kxSkeletonChrome("正在加载每日推荐")
    }
}

/// 二维码未生成时的占位：白底内一块 210 方形灰块，不转圈、不抖动。
/// 这里不能套 kxSkeletonChrome（它会把视图撑满宽度并左对齐），否则灰块在 230 白卡里会偏左。
struct KXQRSkeleton: View {
    var body: some View {
        KXSkelBar(w: 210, h: 210, r: 8)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在生成二维码")
    }
}

/// 收藏 / 最近播放等单列列表的骨架（首次云同步期间替代「暂无内容」空态）。
struct KXListSkeleton: View {
    var rows: Int = 10
    var circular: Bool = false
    private let fill = Color(.secondarySystemFill)
    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        KXSkelBar(w: w, h: h, r: r)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    if circular {
                        Circle().fill(fill).frame(width: 44, height: 44)
                    } else {
                        bar(46, 46, KXRadius.cover)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        bar(150, 13); bar(96, 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                Divider().padding(.leading, 58)
            }
        }
        .padding(.horizontal, 16)
        .kxSkeletonChrome("正在加载列表")
    }
}

/// 首页专用骨架：按真实首屏顺序与尺寸占位（热搜胶囊 → 2.7:1 banner → 每日推荐
/// → 推荐歌单画廊 → 榜单行 → 新歌行）。通用 KXSkeletonList 是「歌手头部 + 歌曲列表」
/// 的形状，用在首页会和数据回来后的轮播/卡片网格差出一整屏，加载完成瞬间剧烈跳动。
struct KXHomeSkeleton: View {
    private let fill = Color(.secondarySystemFill)

    private func bar(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(fill)
            .frame(width: w, height: h)
    }
    private func sectionHead(_ w: CGFloat) -> some View {
        bar(w, 18, 5).padding(.horizontal, 16)
    }
    private func cardRow(cover: CGFloat, count: Int, gap: CGFloat) -> some View {
        // 真实首页的每日推荐 / 推荐歌单都是横向 ScrollView。骨架若用裸 HStack，
        // 4 张 110pt 卡片总宽 476pt 会把外层 VStack 撑到比屏幕还宽，
        // 于是整块骨架被居中摆放：左边被裁、右边越界，看上去和真实布局差很远。
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        bar(cover, cover, 12)
                        bar(cover * 0.78, 12)
                        bar(cover * 0.52, 10)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: cover + 34)   // 封面 + 间距6 + 标题12 + 间距6 + 描述10
    }
    private func listRow(cover: CGFloat) -> some View {
        HStack(spacing: 12) {
            bar(cover, cover, 9)
            VStack(alignment: .leading, spacing: 6) {
                bar(150, 13)
                bar(100, 10)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    var body: some View {
        let cardW = UIScreen.main.bounds.width - 38
        VStack(alignment: .leading, spacing: 18) {
            bar(72, 12).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array([64, 86, 72, 96, 68].enumerated()), id: \.offset) { _, w in
                        Capsule().fill(fill).frame(width: CGFloat(w), height: 28)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 28)

            bar(cardW, round(cardW / 2.7), 18).padding(.horizontal, 16)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(fill).frame(width: i == 0 ? 16 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)

            sectionHead(88)                                  // 每日推荐
            cardRow(cover: 110, count: 4, gap: 12)
            sectionHead(88)                                  // 推荐歌单
            cardRow(cover: 130, count: 3, gap: 6)
            sectionHead(64)                                  // 排行榜
            ForEach(0..<3, id: \.self) { _ in listRow(cover: 56) }
            sectionHead(80)                                  // 新歌速递
            ForEach(0..<3, id: \.self) { _ in listRow(cover: 46) }
        }
        // 钉死为视口宽度并左对齐，任何子行都不得再把骨架整体撑宽/居中
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载首页")
    }
}
