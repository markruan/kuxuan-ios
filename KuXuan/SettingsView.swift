import SwiftUI

/// 设置页：从个人中心底部列表 push 进来，因此不再自带 NavigationStack。
/// 颜色统一：状态圆点、账号图标、勾选都用品牌色 .kxAccent，不再混用系统绿/橙。
struct SettingsView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    @State private var status: String = ""
    @State private var service: ServiceStatus?
    @State private var quality: String = APIClient.audioQuality
    @AppStorage("kuxuan_lyrics_style") private var lyricsStyleRaw: String = LyricsStyle.miSide.rawValue

    var body: some View {
        Form {
            Section("全屏歌词样式") {
                Picker("显示样式", selection: $lyricsStyleRaw) {
                    ForEach(LyricsStyle.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                Text("可在播放页点「全屏」查看效果；后续会增加更多样式。")
                    .font(.caption2).foregroundColor(.secondary)
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

            Section("本机服务") {
                if let s = service {
                    row("本地曲库", "\(s.library) 首")
                    row("上游音源", s.onlineApi)
                } else {
                    Text("读取失败，请确认后端服务正在运行")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }

            Section("网易云账号") {
                HStack(spacing: 8) {
                    KXIcon(icon: auth.ncmBound ? .checkCircle : .person,
                           size: 18, color: .kxAccent)
                    Text(auth.ncmBound ? "已绑定" : "未绑定")
                    Spacer()
                    Text(auth.ncmProfile?.nickname ?? "未绑定")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Text("绑定后，点 ♡ 收藏会同步到网易云「我喜欢的音乐」；也可新建歌单、把歌曲加入歌单。解绑后仅保存在本机。")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section {
                Text("服务已部署在云端，手机使用移动网络或 Wi-Fi 均可直接访问，无需与本机同一网络。")
                    .font(.footnote).foregroundColor(.secondary)
            } header: { Text("如何连接") }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .kxBackBar()
        .task {
            status = ""
            quality = APIClient.audioQuality
            service = try? await APIClient.serviceStatus()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.footnote)
            Spacer()
            Text(value).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
    }

    private func test() async {
        do {
            let h = try await APIClient.home()
            status = h.online ? "连接成功，在线音源可用" : "已连接，但上游暂不可用（\(h.statusText)）"
            service = try? await APIClient.serviceStatus()
        } catch {
            status = "连接失败：\(error.localizedDescription)"
        }
    }
}
