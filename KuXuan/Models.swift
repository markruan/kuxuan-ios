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

struct LyricLine: Identifiable {
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
