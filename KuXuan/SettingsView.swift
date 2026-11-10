import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss
    @State private var urlText: String = APIClient.baseURL
    @State private var status: String = ""
    @State private var service: ServiceStatus?
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.10.102:8765/", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存并测试连接") { Task { await test() } }
                        .tint(.kxAccent)
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("服务器地址")
                } footer: {
                    Text("保存后首页下拉刷新即可生效；播放中的歌曲仍走旧连接。")
                        .font(.caption2)
                }

                Section("连接状态") {
                    HStack {
                        Circle().fill(status.hasPrefix("连接成功") ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(status.isEmpty ? "尚未测试" : status)
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section("本机服务") {
                    if let s = service {
                        row("本地曲库", "\(s.library) 首")
                        row("上游音源", s.onlineApi)
                        row("局域网", "\(s.ip):\(s.port)")
                    } else {
                        Text("读取失败，请确认 server.py 正在运行")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section("账号") {
                    HStack {
                        Label(auth.isLoggedIn ? "已登录" : "未登录",
                              systemImage: auth.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                        Spacer()
                        Text(auth.displayName).font(.footnote).foregroundColor(.secondary)
                    }
                    Button("打开个人中心") { showAccount = true }
                        .tint(.kxAccent)
                }

                Section {
                    Text("在 Mac 上运行 `bash start_server.sh`（kuxuan-ios 目录），并保持 iPhone 与 Mac 处于同一 Wi-Fi。手机通过局域网地址访问该服务。")
                        .font(.footnote).foregroundColor(.secondary)
                } header: { Text("如何连接") }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
            .task {
                status = ""
                service = try? await APIClient.serviceStatus()
            }
            .sheet(isPresented: $showAccount) {
                AccountCenterView()
                    .environmentObject(player)
                    .environmentObject(auth)
            }
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
        APIClient.baseURL = urlText
        do {
            let h = try await APIClient.home()
            status = h.online ? "连接成功，在线音源可用" : "已连接，但上游暂不可用（\(h.statusText)）"
            service = try? await APIClient.serviceStatus()
        } catch {
            status = "连接失败：\(error.localizedDescription)"
        }
    }
}
