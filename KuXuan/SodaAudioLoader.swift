import Foundation

/// 汽水解密音频加载器。
///
/// 汽水 VIP 整曲是加密流（spade/CENC），需签名器 + 本地 AES-CTR 解密才能播。
/// 解密在本地 Rust bridge（`soda-bridge`）里完成：bridge 的 `/play/{id}` 端点
/// 调用 libresoda 的 `Soda::download` 把加密流下载并解密成明文 m4a，再经
/// server.py 转发把字节回给 App。Swift 侧只负责把这些字节落盘成临时文件，
/// 交给 AVPlayer 播放 —— 因此无需在 Swift 里移植加密算法。
final class SodaAudioLoader {
    static let shared = SodaAudioLoader()
    private let session: URLSession
    private var cache: [String: URL] = [:]
    private let cacheQueue = DispatchQueue(label: "com.kuxuan.soda.cache")

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 180
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    /// 取某 track id 的可播放本地文件 URL。同一 id 命中本地缓存，避免重复解密下载。
    func load(trackId: String) async throws -> URL {
        if let cached = cacheQueue.sync(execute: { cache[trackId] }) {
            return cached
        }
        guard let url = APIClient.sodaPlayURL(trackId) else {
            throw SodaPlayError.unavailable
        }
        let (data, response) = try await session.data(from: url)
        // bridge 出错时回的是 JSON（403/502），不能当成音频写盘。
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = msg["error"] as? String {
                throw SodaPlayError.bridge(err)
            }
            throw SodaPlayError.unavailable
        }
        // 防御：若响应体以 '{' 开头，基本是错误 JSON 而非音频头。
        if let first = data.first, first == UInt8(ascii: "{") {
            throw SodaPlayError.unavailable
        }
        let file = tempURL(for: trackId)
        try data.write(to: file, options: .atomic)
        cacheQueue.sync { cache[trackId] = file }
        return file
    }

    private func tempURL(for id: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuxuan_soda", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return dir.appendingPathComponent("\(safe).m4a")
    }
}

enum SodaPlayError: LocalizedError {
    case unavailable
    case bridge(String)
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "汽水音频暂时无法播放（未绑定或桥接离线）"
        case .bridge(let m):
            return m
        }
    }
}
