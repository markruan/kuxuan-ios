import Foundation

// 所有模型用字典手动解析（JSONSerialization），每个字段都带回退，
// 避免因为某个字段类型不符（如 id 是数字而非字符串）导致整页解码失败。

struct Song: Identifiable, Equatable {
    let id: String
    let file: String
    let title: String
    let artist: String
    let artistId: String   // 歌手 id（后端 _norm_song 已透传，用于跳转到歌手页/收藏歌手）
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
        self.artistId = (dict["artistId"] as? String) ?? ""
        self.album = (dict["album"] as? String) ?? ""
        let d = dict["duration"] as? Double ?? Double(dict["duration"] as? Int ?? 0)
        self.duration = d
        self.hasLyric = (dict["hasLyric"] as? Bool) ?? false
        self.cover = (dict["cover"] as? String) ?? ""
        self.picUrl = (dict["picUrl"] as? String) ?? ""
        self.online = (dict["online"] as? Bool) ?? false
    }
}

extension Song {
    /// 可写入网易云「我喜欢的音乐」的真实歌曲 id。
    /// 后端 _norm_song 给所有在线歌曲统一加 "online:" 前缀（如 online:1964713291），
    /// 而上游 /like 只接受纯数字 id。此前 toggleFav 直接判断 song.id 是否纯数字，
    /// 结果所有在线歌曲都被误判为「本地曲目」，收藏只写本机 —— 即「假收藏」的根因。
    var ncmID: String? {
        let raw = id.hasPrefix("online:") ? String(id.dropFirst("online:".count)) : id
        return !raw.isEmpty && raw.allSatisfy({ $0.isNumber }) ? raw : nil
    }
}

// MARK: - 云端红心列表（/api/ncm/likelist）
struct NCMLikeListResp {
    let ids: [String]
    let songs: [Song]
    let count: Int
    init(dict: [String: Any]) {
        ids = (dict["ids"] as? [Any] ?? []).map { String(describing: $0) }
        songs = (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        count = (dict["count"] as? Int) ?? ids.count
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

/// 逐字歌词：单字/词在整首歌里的绝对开始时间与持续时长（秒）
struct LyricWord: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let duration: Double
    let text: String
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
    var words: [LyricWord] = []     // 逐字（yrc）可选，空则按整行高亮
    var translation: String = ""     // 翻译（tlyric）可选
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

// MARK: - 逐字歌词（网易云 yrc 增强格式）
/// yrc 形如：[0,1000](0,235,0)词(235,308,0)儿(543,344,0)啊
/// 行内 [startMs,endMs] 为整行时间；每个 (relMs,durMs,0)词 为逐字相对时间+时长。
func parseYRC(_ text: String) -> [(time: Double, words: [LyricWord])] {
    var out: [(Double, [LyricWord])] = []
    guard let lineRe = try? NSRegularExpression(pattern: #"\[(\d+),\d+\]([\s\S]*)"#),
          let wordRe = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)([\s\S]*?)(?=\(|\Z)"#) else {
        return out
    }
    for raw in text.components(separatedBy: "\n") {
        let ns = raw as NSString
        guard let lm = lineRe.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { continue }
        guard let ls = Double(ns.substring(with: lm.range(at: 1))) else { continue }
        let body = ns.substring(with: lm.range(at: 2))
        var words: [LyricWord] = []
        let bns = body as NSString
        for wm in wordRe.matches(in: body, range: NSRange(location: 0, length: bns.length)) {
            let rel = Double(bns.substring(with: wm.range(at: 1))) ?? 0
            let dur = Double(bns.substring(with: wm.range(at: 2))) ?? 0
            let wtext = bns.substring(with: wm.range(at: 3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if wtext.isEmpty { continue }
            words.append(LyricWord(time: (ls + rel) / 1000.0,
                                  duration: dur / 1000.0,
                                  text: wtext))
        }
        if !words.isEmpty { out.append((ls / 1000.0, words)) }
    }
    return out
}

/// 解析普通 LRC，再把逐字(yrc)与翻译(tlyric)按时间就近合并到各行。
func parseEnhancedLyrics(lrc: String, yrc: String, tlyric: String) -> [LyricLine] {
    var lines = parseLRC(lrc)
    guard !lines.isEmpty else { return lines }

    if !yrc.isEmpty {
        let ylines = parseYRC(yrc)
        for i in lines.indices {
            if let best = ylines.min(by: {
                abs($0.time - lines[i].time) < abs($1.time - lines[i].time)
            }), abs(best.time - lines[i].time) < 0.6 {
                lines[i].words = best.words
            }
        }
    }
    if !tlyric.isEmpty {
        let tl = parseLRC(tlyric)
        for i in lines.indices {
            if let best = tl.min(by: {
                abs($0.time - lines[i].time) < abs($1.time - lines[i].time)
            }), abs(best.time - lines[i].time) < 0.6 {
                lines[i].translation = best.text
            }
        }
    }
    return lines
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
    let subscribed: Bool
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "未命名歌单"
        self.cover = (dict["cover"] as? String) ?? ""
        self.trackCount = (dict["trackCount"] as? Int) ?? 0
        self.creator = (dict["creator"] as? String) ?? ""
        self.subscribed = (dict["subscribed"] as? Bool) ?? false
    }

    /// 成员构造器：用于本地同步收藏状态（无需重打接口）。
    init(id: String, name: String, cover: String, trackCount: Int, creator: String, subscribed: Bool) {
        self.id = id; self.name = name; self.cover = cover
        self.trackCount = trackCount; self.creator = creator; self.subscribed = subscribed
    }
}

// MARK: - 搜索：歌手 / 歌单
struct NCMArtist: Identifiable {
    let id: String
    let name: String
    let cover: String
    let albumSize: Int
    let musicSize: Int
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "未知歌手"
        self.cover = (dict["cover"] as? String) ?? ""
        self.albumSize = (dict["albumSize"] as? Int) ?? 0
        self.musicSize = (dict["musicSize"] as? Int) ?? 0
    }
}

struct NCMSearchPlaylist: Identifiable {
    let id: String
    let name: String
    let cover: String
    let playCount: Int64
    let trackCount: Int64
    let creator: String
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "歌单"
        self.cover = (dict["cover"] as? String) ?? ""
        self.playCount = int64(dict["playCount"])
        self.trackCount = int64(dict["trackCount"])
        self.creator = (dict["creator"] as? String) ?? ""
    }
    var playCountText: String {
        if playCount >= 100_000_000 { return String(format: "%.1f亿", Double(playCount) / 100_000_000) }
        if playCount >= 10_000 { return String(format: "%.1f万", Double(playCount) / 10_000) }
        return "\(playCount)"
    }
}

// MARK: - 歌手详情（/api/online/artist/<id>/detail）
/// 轻量歌手：用于「打开歌手页 / 相似歌手 / 收藏列表」的最小信息。
/// 同时是 Identifiable + Equatable，可直接作为 fullScreenCover(item:) 的 item。
struct MiniArtist: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let cover: String
    init(id: String, name: String, cover: String) {
        self.id = id; self.name = name; self.cover = cover
    }
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "未知歌手"
        self.cover = (dict["cover"] as? String) ?? ""
    }
}

/// 专辑（歌手详情里的 hotAlbums）
struct ArtistAlbum: Identifiable {
    let id: String
    let name: String
    let cover: String
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? ""
        self.cover = (dict["cover"] as? String) ?? ""
    }
}

/// 歌手详情：头部信息 + 热门歌曲 + 专辑 + 相似歌手
struct KBArtistDetail {
    let id: String
    let name: String
    let cover: String
    let albumSize: Int
    let musicSize: Int
    let briefDesc: String
    let introduction: [(title: String, text: String)]
    init(dict: [String: Any]) {
        self.id = String(describing: dict["id"] ?? "")
        self.name = (dict["name"] as? String) ?? "未知歌手"
        self.cover = (dict["cover"] as? String) ?? ""
        self.albumSize = (dict["albumSize"] as? Int) ?? 0
        self.musicSize = (dict["musicSize"] as? Int) ?? 0
        self.briefDesc = (dict["briefDesc"] as? String) ?? ""
        var intro: [(title: String, text: String)] = []
        if let arr = dict["introduction"] as? [[String: Any]] {
            for it in arr {
                let t = (it["ti"] as? String) ?? ""
                let x = (it["txt"] as? String) ?? ""
                if !t.isEmpty || !x.isEmpty { intro.append((t, x)) }
            }
        }
        self.introduction = intro
    }
    /// 合并简介正文：一句话简介（briefDesc）+ 分段介绍（introduction）
    var bioText: String {
        var parts: [String] = []
        if !briefDesc.isEmpty { parts.append(briefDesc) }
        for (t, x) in introduction where !x.isEmpty {
            parts.append((t.isEmpty ? "" : t + "\n") + x)
        }
        return parts.joined(separator: "\n\n")
    }
}

struct ArtistDetailResp {
    let code: Int
    let artist: KBArtistDetail
    let songs: [Song]
    let albums: [ArtistAlbum]
    let similar: [MiniArtist]
    init(dict: [String: Any]) {
        self.code = (dict["code"] as? Int) ?? 200
        self.artist = KBArtistDetail(dict: dict["artist"] as? [String: Any] ?? [:])
        self.songs = (dict["songs"] as? [[String: Any]] ?? []).map { Song(dict: $0) }
        self.albums = (dict["albums"] as? [[String: Any]] ?? []).map { ArtistAlbum(dict: $0) }
        self.similar = (dict["similar"] as? [[String: Any]] ?? []).map { MiniArtist(dict: $0) }
    }
}

/// 收藏歌手列表（/api/ncm/artist/sublist），与网易云「关注」同步
struct FavArtistListResp {
    let ok: Bool
    let artists: [MiniArtist]
    let count: Int
    init(dict: [String: Any]) {
        self.ok = (dict["ok"] as? Bool) ?? false
        self.artists = (dict["artists"] as? [[String: Any]] ?? []).map { MiniArtist(dict: $0) }
        self.count = (dict["count"] as? Int) ?? self.artists.count
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
