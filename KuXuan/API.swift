import Foundation
import UIKit

enum KXError: Error { case message(String) }

struct APIClient {

    // MARK: - 服务器地址（可配置，持久化到 UserDefaults）
    static var baseURL: String {
        get {
            let s = UserDefaults.standard.string(forKey: "kuxuan_server")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? "http://192.168.10.102:8765/" : s
        }
        set {
            var s = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.hasSuffix("/") { s += "/" }
            UserDefaults.standard.set(s, forKey: "kuxuan_server")
        }
    }

    // 把相对路径（/api/online/cover/...）或绝对 URL 转成完整 URL
    static func abs(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + p.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    // 音频流地址
    static func streamURL(_ file: String?) -> URL? {
        guard let f = file, !f.isEmpty else { return nil }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/api/online/stream/" + f)
    }

    // 把 /api/online/cover/.. 之类相对路径拼成完整 URL 字符串（供 SwiftUI 的 AsyncImage 用）
    static func coverURL(_ path: String?) -> URL? { abs(path) }

    private static func getJSON(_ path: String) async throws -> [String: Any] {
        guard let url = abs(path) else { throw KXError.message("非法地址") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KXError.message("返回不是 JSON 对象")
        }
        return obj
    }

    static func home() async throws -> HomeResp {
        let dict = try await getJSON("/api/online/home")
        return HomeResp(dict: dict)
    }

    static func playlist(id: String) async throws -> PlaylistDetailResp {
        let dict = try await getJSON("/api/online/playlist/" + id)
        return PlaylistDetailResp(dict: dict)
    }

    // 歌词是纯文本 LRC，不是 JSON
    static func lyric(file: String) async throws -> String {
        guard let url = abs("/api/online/lyric/" + file) else { throw KXError.message("非法地址") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func search(q: String) async throws -> [Song] {
        let dict = try await getJSON("/api/online/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        let songs = (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        return songs
    }

    // 下载封面图（用于取主色 / 锁屏封面）
    static func fetchImage(_ path: String?) async -> UIImage? {
        guard let url = abs(path) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }
}
