import SwiftUI

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
