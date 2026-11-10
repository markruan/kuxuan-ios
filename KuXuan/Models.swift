import Foundation

// 所有模型用字典手动解析（JSONSerialization），每个字段都带回退，
// 避免因为某个字段类型不符（如 id 是数字而非字符串）导致整页解码失败。

struct Song: Identifiable, Equatable {
    let id: String
    let file: String
    let title: String
    let artist: String
    let album: String
    let duration: Double   // 秒
    let hasLyric: Bool
    let cover: String
    let picUrl: String
    let online: Bool

    init(dict: [String: Any]) {
        let rawId = dict["id"]
        self.id = (rawId as? String) ?? ("online:" + String(describing: rawId ?? ""))
        self.file = String(describing: dict["file"] ?? "")
        self.title = (dict["title"] as? String) ?? "未知歌曲"
        self.artist = (dict["artist"] as? String) ?? "未知艺术家"
        self.album = (dict["album"] as? String) ?? ""
        let d = dict["duration"] as? Double ?? Double(dict["duration"] as? Int ?? 0)
        self.duration = d
        self.hasLyric = (dict["hasLyric"] as? Bool) ?? false
        self.cover = (dict["cover"] as? String) ?? ""
        self.picUrl = (dict["picUrl"] as? String) ?? ""
        self.online = (dict["online"] as? Bool) ?? false
    }
}

struct Playlist: Identifiable {
    let id: String
    let name: String
    let cover: String
    let playCount: Int64
    let trackCount: Int64
    let description: String

    init(dict: [String: Any]) {
        let rawId = dict["id"]
        self.id = (rawId as? String) ?? String(describing: rawId ?? "")
        self.name = (dict["name"] as? String) ?? "歌单"
        self.cover = (dict["cover"] as? String) ?? ""
        self.playCount = int64(dict["playCount"])
        self.trackCount = int64(dict["trackCount"])
        self.description = (dict["description"] as? String) ?? ""
    }

    var playCountText: String {
        if playCount >= 100_000_000 { return String(format: "%.1f亿", Double(playCount) / 100_000_000) }
        if playCount >= 10_000 { return String(format: "%.1f万", Double(playCount) / 10_000) }
        return "\(playCount)"
    }
}

struct ChartTrack { let title: String; let artist: String }

struct Chart: Identifiable {
    let id: String
    let name: String
    let cover: String
    let update: String
    let tracks: [ChartTrack]

    init(dict: [String: Any]) {
        let rawId = dict["id"]
        self.id = (rawId as? String) ?? String(describing: rawId ?? "")
        self.name = (dict["name"] as? String) ?? ""
        self.cover = (dict["cover"] as? String) ?? ""
        self.update = (dict["update"] as? String) ?? ""
        var tr: [ChartTrack] = []
        if let arr = dict["tracks"] as? [[String: Any]] {
            for t in arr { tr.append(ChartTrack(title: (t["title"] as? String) ?? "",
                                                artist: (t["artist"] as? String) ?? "")) }
        } else if let arr = dict["tracks"] as? [String] {
            for s in arr { tr.append(ChartTrack(title: s, artist: "")) }
        }
        self.tracks = tr
    }
}

struct Banner {
    let img: String
    let title: String
    let id: String
    init(dict: [String: Any]) {
        self.img = (dict["img"] as? String) ?? ""
        self.title = (dict["title"] as? String) ?? ""
        self.id = String(describing: dict["id"] ?? "")
    }
}

struct HomeResp {
    let banners: [Banner]
    let playlists: [Playlist]
    let charts: [Chart]
    let newsongs: [Song]
    let hot: [String]
    let status: [String: Any]?
    init(dict: [String: Any]) {
        banners = (dict["banners"] as? [[String: Any]] ?? []).map { Banner(dict: $0) }
        playlists = (dict["playlists"] as? [[String: Any]] ?? []).map { Playlist(dict: $0) }
        charts = (dict["charts"] as? [[String: Any]] ?? []).map { Chart(dict: $0) }
        newsongs = (dict["newsongs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        hot = (dict["hot"] as? [String] ?? [])
        status = dict["status"] as? [String: Any]
    }
    var online: Bool { (status?["playable"] as? Bool) ?? false }
    var statusText: String {
        if let r = status?["riskControl"] as? Bool, r { return "上游风控中" }
        if online { return "在线音源可用" }
        return "离线"
    }
}

struct PlaylistDetailResp {
    let code: Int
    let info: Playlist?
    let songs: [Song]
    let reason: String
    init(dict: [String: Any]) {
        self.code = (dict["code"] as? Int) ?? 200
        self.info = (dict["info"] as? [String: Any]).map { Playlist(dict: $0) }
        self.songs = (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        self.reason = (dict["reason"] as? String) ?? ""
    }
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

func int64(_ v: Any?) -> Int64 {
    if let n = v as? Int64 { return n }
    if let n = v as? Int { return Int64(n) }
    if let n = v as? Double { return Int64(n) }
    if let s = v as? String, let n = Int64(s) { return n }
    return 0
}

func parseLRC(_ text: String) -> [LyricLine] {
    var out: [LyricLine] = []
    guard let re = try? NSRegularExpression(pattern: #"\[(\d+):(\d+)(?:[.:](\d+))?\]"#) else { return out }
    for raw in text.components(separatedBy: "\n") {
        let ns = raw as NSString
        let matches = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        let times: [Double] = matches.compactMap { m in
            let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
            var frac = 0.0
            if m.range(at: 3).location != NSNotFound {
                let fs = ns.substring(with: m.range(at: 3))
                let denom = fs.count == 2 ? 100.0 : 1000.0
                frac = (Double(fs) ?? 0) / denom
            }
            return min * 60 + sec + frac
        }
        let txt = re.stringByReplacingMatches(in: raw,
                                              range: NSRange(location: 0, length: ns.length),
                                              withTemplate: "").trimmingCharacters(in: .whitespaces)
        for t in times { out.append(LyricLine(time: t, text: txt)) }
    }
    return out.sorted { $0.time < $1.time }
}

// MARK: - 账号体系（/api/auth/*）
struct KXUser {
    let id: Int
    let username: String
    let nickname: String
    let createdAt: Int
    let lastLogin: Int
    init(dict: [String: Any]) {
        self.id = (dict["id"] as? Int) ?? 0
        self.username = (dict["username"] as? String) ?? ""
        self.nickname = (dict["nickname"] as? String) ?? ""
        self.createdAt = (dict["createdAt"] as? Int) ?? 0
        self.lastLogin = (dict["lastLogin"] as? Int) ?? 0
    }
    var createdText: String { Self.dateText(createdAt) }
    var loginText: String { Self.dateText(lastLogin) }
    private static func dateText(_ t: Int) -> String {
        guard t > 0 else { return "—" }
        let d = Date(timeIntervalSince1970: TimeInterval(t))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

struct AuthStatusResp {
    let requireAuth: Bool
    let allowRegister: Bool
    let userCount: Int
    let sessionDays: Int
    let user: KXUser?
    init(dict: [String: Any]) {
        self.requireAuth = (dict["requireAuth"] as? Bool) ?? false
        self.allowRegister = (dict["allowRegister"] as? Bool) ?? true
        self.userCount = (dict["userCount"] as? Int) ?? 0
        self.sessionDays = (dict["sessionDays"] as? Int) ?? 0
        self.user = (dict["user"] as? [String: Any]).map { KXUser(dict: $0) }
    }
}

// MARK: - 网易云账号（/api/ncm/*）
struct NCMProfile {
    let uid: String
    let nickname: String
    let avatar: String
    let boundAt: Int
    init(dict: [String: Any]) {
        self.uid = String(describing: dict["uid"] ?? "")
        self.nickname = (dict["nickname"] as? String) ?? ""
        self.avatar = (dict["avatar"] as? String) ?? ""
        self.boundAt = (dict["boundAt"] as? Int) ?? 0
    }
}

struct NCMMeResp {
    let bound: Bool
    let profile: NCMProfile?
    init(dict: [String: Any]) {
        self.bound = (dict["bound"] as? Bool) ?? false
        self.profile = (dict["profile"] as? [String: Any]).map { NCMProfile(dict: $0) }
    }
}

struct NCMPlaylist: Identifiable {
    let id: String
    let name: String
    let cover: String
    let trackCount: Int
    let creator: String
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "未命名歌单"
        self.cover = (dict["cover"] as? String) ?? ""
        self.trackCount = (dict["trackCount"] as? Int) ?? 0
        self.creator = (dict["creator"] as? String) ?? ""
    }
}

// MARK: - 歌曲评论（/api/online/comment/<id>）
struct KXComment: Identifiable {
    let id: String
    let user: String
    let avatar: String
    let content: String
    let time: Int64
    let timeStr: String
    let liked: Int
    let quote: String
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? UUID().uuidString)
        self.user = (dict["user"] as? String) ?? "匿名用户"
        self.avatar = (dict["avatar"] as? String) ?? ""
        self.content = (dict["content"] as? String) ?? ""
        self.time = int64(dict["time"])
        self.timeStr = (dict["timeStr"] as? String) ?? ""
        self.liked = (dict["liked"] as? Int) ?? 0
        self.quote = (dict["quote"] as? String) ?? ""
    }
    var likedText: String {
        if liked >= 10000 { return String(format: "%.1f万", Double(liked) / 10000) }
        return "\(liked)"
    }
    var displayTime: String {
        if !timeStr.isEmpty { return timeStr }
        guard time > 0 else { return "" }
        let d = Date(timeIntervalSince1970: TimeInterval(time) / 1000)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

struct CommentResp {
    let total: Int
    let hot: [KXComment]
    let comments: [KXComment]
    let more: Bool
    init(dict: [String: Any]) {
        self.total = (dict["total"] as? Int) ?? 0
        self.hot = (dict["hot"] as? [[String: Any]] ?? []).map { KXComment(dict: $0) }
        self.comments = (dict["comments"] as? [[String: Any]] ?? []).map { KXComment(dict: $0) }
        self.more = (dict["more"] as? Bool) ?? false
    }
}

// MARK: - 可播性 / 服务状态
struct ResolveResp {
    let playable: Bool
    let br: Int
    let level: String
    let trial: Bool
    let reason: String
    init(dict: [String: Any]) {
        self.playable = (dict["playable"] as? Bool) ?? false
        self.br = (dict["br"] as? Int) ?? 0
        self.level = (dict["level"] as? String) ?? ""
        self.trial = (dict["trial"] as? Bool) ?? false
        self.reason = (dict["reason"] as? String) ?? ""
    }
    var qualityText: String {
        guard playable else { return "不可播放" }
        let kbps = br > 0 ? "\(br / 1000) kbps" : (level.isEmpty ? "标准" : level)
        return trial ? "\(kbps) · 试听片段" : kbps
    }
}

struct ServiceStatus {
    let library: Int
    let ip: String
    let port: Int
    let onlineApi: String
    init(dict: [String: Any]) {
        self.library = (dict["library"] as? Int) ?? 0
        self.ip = (dict["ip"] as? String) ?? ""
        self.port = (dict["port"] as? Int) ?? 0
        self.onlineApi = (dict["onlineApi"] as? String) ?? ""
    }
}
