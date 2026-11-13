import Foundation
import UIKit

enum KXError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}

/// KuXuan 后端全部能力的统一入口。
/// 后端是云端部署的 server.py（默认 http://47.99.97.84:8765/），
/// 账号类接口用 Authorization: Bearer <token>（与 Web 端一致）。
struct APIClient {

    // MARK: - 服务器地址（打包内置默认云端地址；历史 UserDefaults 仍可被读取，App 不再提供编辑/展示入口）
    static var baseURL: String {
        get {
            let s = UserDefaults.standard.string(forKey: "kuxuan_server")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? "http://47.99.97.84:8765/" : s
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

    /// 严格的 query 百分号编码。
    /// .urlQueryAllowed 会放行 & = + ? 等保留字符，用户输入的评论/歌单名/搜索词里
    /// 只要出现这些字符就会把 query 截断，导致内容丢失甚至参数错位。
    /// 因此只保留 RFC 3986 的 unreserved 字符集，中文等非 ASCII 一并编码。
    static func kxQueryEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - 音质（只暴露实测真正有效的 3 档）
    // 实测：免费歌曲 standard=128k / higher=192k / exhigh=320k；
    // lossless 及以上在当前账号下全部回落 320k，VIP 歌曲一律 128k 试听片段。
    struct QualityOption: Identifiable {
        let key: String
        let name: String
        let detail: String
        var id: String { key }
    }
    static let qualityOptions: [QualityOption] = [
        QualityOption(key: "standard", name: "标准", detail: "128 kbps · 省流量"),
        QualityOption(key: "higher",  name: "较高", detail: "192 kbps"),
        QualityOption(key: "exhigh",  name: "极高", detail: "320 kbps · 建议 Wi-Fi"),
    ]
    static var audioQuality: String {
        get {
            let s = UserDefaults.standard.string(forKey: "kuxuan_quality") ?? ""
            return qualityOptions.contains { $0.key == s } ? s : "standard"
        }
        set { UserDefaults.standard.set(newValue, forKey: "kuxuan_quality") }
    }
    static var audioQualityName: String {
        qualityOptions.first { $0.key == audioQuality }?.name ?? "标准"
    }
    static var audioQualityDetail: String {
        qualityOptions.first { $0.key == audioQuality }?.detail ?? "128 kbps"
    }

    /// 播放地址带上所选档位；切换后只对下一首生效（当前曲目已建立连接）。
    static func streamURL(_ file: String?) -> URL? {
        guard let f = file, !f.isEmpty else { return nil }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/api/online/stream/" + f + "?level=" + audioQuality)
    }

    /// 列表小缩略图无需拉原图。网易云 CDN（p*.music.126.net）支持 ?param=WyH
    /// 服务端降采样，传 size 后追加该参数可大幅减少下载量、加速首屏。
    static func coverURL(_ path: String?, size: Int? = nil) -> URL? {
        guard let u = abs(path) else { return nil }
        guard let size = size, size > 0 else { return u }
        if u.host?.contains("126.net") == true {
            let sep = (u.query ?? "").isEmpty ? "?" : "&"
            return URL(string: u.absoluteString + sep + "param=\(size)y\(size)")
        }
        return u
    }

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

    /// 逐字歌词 JSON：{lrc, yrc, tlyric, romalrc}
    static func lyricJSON(file: String) async throws -> [String: Any] {
        guard let url = abs("/api/online/lyricjson/" + file) else { throw KXError.message("非法地址") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KXError.message("歌词解析失败")
        }
        return dict
    }

    static func search(q: String) async throws -> [Song] {
        let enc = kxQueryEncode(q)
        let dict = try await getJSON("/api/online/search?q=" + enc)
        return (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
    }

    /// 搜索歌手（type=artists）：返回歌手列表，封面走后端图片代理。
    static func searchArtists(q: String) async throws -> [NCMArtist] {
        let enc = kxQueryEncode(q)
        let dict = try await getJSON("/api/online/search?q=" + enc + "&type=artists")
        return (dict["artists"] as? [[String: Any]] ?? []).map { NCMArtist(dict: $0) }
    }

    /// 搜索歌单（type=playlists）：返回歌单列表。
    static func searchPlaylists(q: String) async throws -> [NCMSearchPlaylist] {
        let enc = kxQueryEncode(q)
        let dict = try await getJSON("/api/online/search?q=" + enc + "&type=playlists")
        return (dict["playlists"] as? [[String: Any]] ?? []).map { NCMSearchPlaylist(dict: $0) }
    }

    /// 歌手热门歌曲：/api/online/artist/<id>/songs，返回统一 Song 列表。
    static func artistSongs(id: String) async throws -> ([Song], NCMArtist) {
        let dict = try await getJSON("/api/online/artist/" + id + "/songs")
        let songs = (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        let artist = NCMArtist(dict: dict["artist"] as? [String: Any] ?? [:])
        return (songs, artist)
    }

    /// 歌手详情（中等丰富度）：/api/online/artist/<id>/detail
    /// 返回头部信息 + 热门歌曲(50) + 专辑(12) + 相似歌手(12) + 简介。
    static func artistDetail(id: String) async throws -> ArtistDetailResp {
        ArtistDetailResp(dict: try await getJSON("/api/online/artist/" + id + "/detail"))
    }

    /// 收藏歌手 = 同步网易云「关注」。后端 /artist/sub 用 t=1 关注、t=0 取消，参数名 id。
    /// 返回 true 表示已关注（写操作成功）。未连接网易云时后端会返回错误，由调用方提示。
    static func artistSub(id: String) async throws -> Bool {
        let t = Int(Date().timeIntervalSince1970 * 1000)
        let d = try await getJSON("/api/ncm/artist/sub?id=\(kxQueryEncode(id))&_t=\(t)")
        return d["subbed"] as? Bool ?? (d["ok"] as? Bool ?? false)
    }

    static func artistUnsub(id: String) async throws -> Bool {
        let t = Int(Date().timeIntervalSince1970 * 1000)
        let d = try await getJSON("/api/ncm/artist/unsub?id=\(kxQueryEncode(id))&_t=\(t)")
        return d["subbed"] as? Bool ?? false
    }

    /// 已收藏（关注）的歌手列表，与网易云真实状态对齐。
    static func artistSublist() async throws -> [MiniArtist] {
        let d = try await getJSON("/api/ncm/artist/sublist")
        return FavArtistListResp(dict: d).artists
    }

    /// 可播性 / 码率 / 是否试听片段（后端 /api/online/resolve/<id>）
    static func resolve(songID: String) async throws -> ResolveResp {
        ResolveResp(dict: try await getJSON("/api/online/resolve/" + songID + "?level=" + audioQuality))
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

    /// 收藏同步：把红心 / 取消红心写入网易云「我喜欢的音乐」。
    /// 后端是 GET 路由，_t 时间戳用于绕过 URLSession / 代理缓存，避免连点被吞请求。
    /// 返回服务端写后回查 /likelist 的核对结果：true 表示云端红心列表已确认变化。
    static func ncmLike(songID: String, like: Bool) async throws -> Bool {
        let t = Int(Date().timeIntervalSince1970 * 1000)
        let path = "/api/ncm/like?id=\(songID)&like=\(like ? "true" : "false")&_t=\(t)"
        let d = try await getJSON(path)
        return d["verified"] as? Bool ?? false
    }

    /// 云端红心列表（含歌曲详情），用于把「我的收藏」与网易云真实状态对齐
    static func ncmLikeList() async throws -> NCMLikeListResp {
        NCMLikeListResp(dict: try await getJSON("/api/ncm/likelist"))
    }

    /// 网易云每日歌曲推荐（已绑定账号走个性化推荐，否则走上游默认推荐）。
    /// 返回统一 Song 列表，可直接交给播放器播放。
    static func ncmDailyRecommend() async throws -> [Song] {
        let d = try await getJSON("/api/ncm/recommend/songs")
        return (d["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
    }

    /// 新建网易云歌单（真实写入账号），返回歌单 id
    static func ncmCreatePlaylist(name: String, privacy: String = "0") async throws -> String {
        let enc = kxQueryEncode(name)
        let d = try await getJSON("/api/ncm/playlist/create?name=\(enc)&privacy=\(privacy)")
        return String(describing: d["id"] ?? "")
    }

    /// 把歌曲加入指定网易云歌单；songID 可带 online: 前缀，后端会剥离
    static func ncmAddToPlaylist(pid: String, songID: String) async throws {
        let enc = kxQueryEncode(songID)
        let t = Int(Date().timeIntervalSince1970 * 1000)
        _ = try await getJSON("/api/ncm/playlist/add?pid=\(pid)&id=\(enc)&_t=\(t)")
    }

    /// 收藏 / 取消收藏网易云歌单（真实写入账号）。subscribe=true 收藏，false 取消。
    /// 后端对业务成败都返回 200，这里直接读 ok/error 文案给前端提示。
    static func ncmSubscribePlaylist(id: String, subscribe: Bool) async throws -> (ok: Bool, error: String?) {
        let t = subscribe ? "1" : "2"
        let d = try await getJSON("/api/ncm/playlist/subscribe?id=\(kxQueryEncode(id))&t=\(t)")
        return (d["ok"] as? Bool ?? false, d["error"] as? String)
    }

    /// 发送 / 回复网易云歌曲评论（真实写入账号）。
    /// commentID 非空表示回复该条评论（上游 t=2），否则发新评论（t=1）。
    /// 内容 1-140 字，前后端都会校验；GET 走严格编码避免 & = + 等字符截断 query。
    static func ncmSendComment(songID: String, content: String,
                               commentID: String? = nil) async throws {
        var path = "/api/ncm/comment/add?id=" + kxQueryEncode(songID)
        path += "&content=" + kxQueryEncode(content)
        if let c = commentID, !c.isEmpty {
            path += "&commentId=" + kxQueryEncode(c)
        }
        path += "&_t=\(Int(Date().timeIntervalSince1970 * 1000))"
        _ = try await getJSON(path)
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
