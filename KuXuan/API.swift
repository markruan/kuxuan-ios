import Foundation
import UIKit

enum KXError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}

/// KuXuan 后端全部能力的统一入口。
/// 后端是本机 server.py（默认 http://192.168.10.102:8765/），
/// 账号类接口用 Authorization: Bearer <token>（与 Web 端一致）。
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

    /// 登录会话 token（服务端 30 天有效）
    static var token: String {
        get { UserDefaults.standard.string(forKey: "kuxuan_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "kuxuan_token") }
    }

    // 把相对路径（/api/online/cover/...）或绝对 URL 转成完整 URL
    static func abs(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + p.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func streamURL(_ file: String?) -> URL? {
        guard let f = file, !f.isEmpty else { return nil }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/api/online/stream/" + f)
    }

    static func coverURL(_ path: String?) -> URL? { abs(path) }

    /// 把网易云外链封面转成后端图片代理，避免 http 混合内容被拦
    static func proxiedPicURL(_ urlString: String?) -> URL? {
        guard let u = urlString, !u.isEmpty else { return nil }
        if u.hasPrefix("/") { return abs(u) }
        let encoded = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return abs("/api/online/pic?u=" + encoded)
    }

    // MARK: - 通用请求（GET / POST + Bearer Token）
    static func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        auth: Bool = false
    ) async throws -> [String: Any] {
        guard let url = abs(path) else { throw KXError.message("非法地址") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth {
            let t = token
            if !t.isEmpty { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KXError.message("服务器返回格式异常")
        }
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw KXError.message(obj["error"] as? String ?? "HTTP \(code)")
        }
        if let ok = obj["ok"] as? Bool, !ok {
            throw KXError.message(obj["error"] as? String ?? "请求失败")
        }
        return obj
    }

    static func getJSON(_ path: String) async throws -> [String: Any] {
        try await request(path)
    }

    // MARK: - 在线音源（原有）
    static func home() async throws -> HomeResp {
        HomeResp(dict: try await getJSON("/api/online/home"))
    }

    static func playlist(id: String) async throws -> PlaylistDetailResp {
        PlaylistDetailResp(dict: try await getJSON("/api/online/playlist/" + id))
    }

    /// 歌词是纯文本 LRC，不是 JSON
    static func lyric(file: String) async throws -> String {
        guard let url = abs("/api/online/lyric/" + file) else { throw KXError.message("非法地址") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func search(q: String) async throws -> [Song] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let dict = try await getJSON("/api/online/search?q=" + enc)
        return (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
    }

    /// 可播性 / 码率 / 是否试听片段（后端 /api/online/resolve/<id>）
    static func resolve(songID: String) async throws -> ResolveResp {
        ResolveResp(dict: try await getJSON("/api/online/resolve/" + songID))
    }

    /// 服务状态（曲库数量、局域网 IP、上游地址）
    static func serviceStatus() async throws -> ServiceStatus {
        ServiceStatus(dict: try await getJSON("/api/status"))
    }

    static func fetchImage(_ path: String?) async -> UIImage? {
        guard let url = abs(path) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    // MARK: - 本地账号体系 /api/auth/*
    static func authStatus() async throws -> AuthStatusResp {
        AuthStatusResp(dict: try await getJSON("/api/auth/status"))
    }

    static func authLogin(username: String, password: String) async throws -> (String, KXUser?) {
        let d = try await request("/api/auth/login", method: "POST",
                                  body: ["username": username, "password": password])
        return (d["token"] as? String ?? "", (d["user"] as? [String: Any]).map { KXUser(dict: $0) })
    }

    static func authRegister(username: String, nickname: String, password: String) async throws -> (String, KXUser?) {
        let d = try await request("/api/auth/register", method: "POST",
                                  body: ["username": username, "nickname": nickname, "password": password])
        return (d["token"] as? String ?? "", (d["user"] as? [String: Any]).map { KXUser(dict: $0) })
    }

    static func authMe() async throws -> KXUser? {
        let d = try await request("/api/auth/me", auth: true)
        return (d["user"] as? [String: Any]).map { KXUser(dict: $0) }
    }

    static func authLogout() async throws {
        _ = try await request("/api/auth/logout", method: "POST", body: [:], auth: true)
    }

    static func authUpdateProfile(nickname: String) async throws -> KXUser? {
        let d = try await request("/api/auth/profile", method: "POST",
                                  body: ["nickname": nickname], auth: true)
        return (d["user"] as? [String: Any]).map { KXUser(dict: $0) }
    }

    static func authChangePassword(old: String, new: String) async throws {
        _ = try await request("/api/auth/password", method: "POST",
                              body: ["oldPassword": old, "newPassword": new], auth: true)
    }

    // MARK: - 网易云扫码登录 /api/ncm/*
    static func ncmMe() async throws -> NCMMeResp {
        NCMMeResp(dict: try await getJSON("/api/ncm/me"))
    }

    static func ncmQRKey() async throws -> String {
        let d = try await getJSON("/api/ncm/qr/key")
        return d["unikey"] as? String ?? ""
    }

    /// 返回二维码 data URI（data:image/png;base64,....）
    static func ncmQRCreate(key: String) async throws -> String {
        let enc = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let d = try await getJSON("/api/ncm/qr/create?key=" + enc)
        return d["qrimg"] as? String ?? ""
    }

    static func ncmQRCheck(key: String) async throws -> [String: Any] {
        let enc = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // code 800/801/802/803 时服务端 ok=true；这里不用通用 request 的 ok 校验误伤
        return try await getJSON("/api/ncm/qr/check?key=" + enc)
    }

    static func ncmPlaylists() async throws -> [NCMPlaylist] {
        let d = try await getJSON("/api/ncm/playlists")
        return (d["playlists"] as? [[String: Any]] ?? []).map { NCMPlaylist(dict: $0) }
    }

    static func ncmUnbind() async throws {
        _ = try await getJSON("/api/ncm/unbind")
    }

    /// 把 data URI 解成 UIImage
    static func imageFromDataURI(_ s: String) -> UIImage? {
        guard let comma = s.firstIndex(of: ",") else { return nil }
        let b64 = String(s[s.index(after: comma)...])
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 歌曲评论（新增后端代理 /api/online/comment/<id>）
    static func comments(songID: String, limit: Int = 20, offset: Int = 0) async throws -> CommentResp {
        let path = "/api/online/comment/\(songID)?limit=\(limit)&offset=\(offset)"
        return CommentResp(dict: try await getJSON(path))
    }
}
