import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var player: PlayerEngine
    @Environment(\.dismiss) var dismiss
    @State private var urlText: String = APIClient.baseURL
    @State private var status: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器地址") {
                    TextField("http://192.168.10.102:8765/", text: $urlText)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Button("保存并测试连接") { Task { await test() } }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("连接状态") {
                    Text(status.isEmpty ? "尚未测试" : status)
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section {
                    Text("在 Mac 上运行 `python3 server.py`（kuxuan-ios 目录），并保持 iPhone 与 Mac 处于同一 Wi‑Fi。手机通过局域网地址访问该服务。")
                        .font(.footnote).foregroundColor(.secondary)
                } header: { Text("如何连接") }
            }
            .navigationTitle("设置")
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func test() async {
        APIClient.baseURL = urlText
        do {
            let h = try await APIClient.home()
            status = h.online ? "连接成功，在线音源可用" : "已连接，但上游暂不可用（\(h.statusText)）"
        } catch {
            status = "连接失败：\(error.localizedDescription)"
        }
    }
}
