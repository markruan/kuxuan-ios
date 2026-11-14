import SwiftUI

/// 设置页：从个人中心底部列表 push 进来，因此不再自带 NavigationStack。
/// 颜色统一：状态圆点、账号图标、勾选都用品牌色 .kxAccent，不再混用系统绿/橙。
struct SettingsView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    @State private var status: String = ""
    @State private var quality: String = APIClient.audioQuality
    @AppStorage("kuxuan_lyrics_style") private var lyricsStyleRaw: String = LyricsStyle.miSide.rawValue

    var body: some View {
        Form {
            Section {
                Picker("显示样式", selection: $lyricsStyleRaw) {
                    ForEach(LyricsStyle.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
            } header: {
                Text("全屏歌词样式")
            } footer: {
                Text(LyricsStyle.current.description)
                    .font(.caption2)
            }

            Section {
                ForEach(APIClient.qualityOptions) { opt in
                    Button {
                        APIClient.audioQuality = opt.key
                        quality = opt.key
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.name).font(.subheadline)
                                Text(opt.detail).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            if quality == opt.key {
                                KXIcon(icon: .check, size: 16, color: .kxAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("播放音质")
            } footer: {
                Text("切换后仅对下一首生效，正在播放的歌曲保持原连接。VIP / 付费歌曲无论选哪档都只有 128 kbps 试听片段；极高 320 kbps 的流量约为标准档的 2.5 倍。")
                    .font(.caption2)
            }

            Section("连接状态") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(status.hasPrefix("连接成功") ? Color.kxAccent : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(status.isEmpty ? "尚未测试" : status)
                        .font(.footnote).foregroundColor(.secondary)
                }
                Button("测试连接") { Task { await test() } }
                    .tint(.kxAccent)
            }

            Section("网易云账号") {
                HStack(spacing: 8) {
                    KXIcon(icon: auth.ncmBound ? .checkCircle : .person,
                           size: 18, color: .kxAccent)
                    Text(auth.ncmBound ? (auth.ncmProfile?.nickname ?? "网易云") : "未连接网易云")
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .task {
            status = ""
            quality = APIClient.audioQuality
        }
    }

    private func test() async {
        do {
            let h = try await APIClient.home()
            status = h.online ? "连接成功，在线音源可用" : "已连接，但上游暂不可用（\(h.statusText)）"
        } catch {
            status = "连接失败：\(error.localizedDescription)"
        }
    }
}
