import Foundation
import SwiftUI
import UIKit

/// 账号状态中心：本地账号体系 + 网易云扫码绑定。
/// 不标 @MainActor 是为了让 App 里的 @StateObject 初始化不被 actor 隔离限制；
/// 所有会写 @Published 的方法都显式标 @MainActor。
final class AuthStore: ObservableObject {

    @Published var token: String = APIClient.token
    @Published var user: KXUser?
    @Published var status: AuthStatusResp?
    @Published var lastError: String?

    @Published var ncmBound: Bool = false
    @Published var ncmProfile: NCMProfile?
    @Published var ncmPlaylists: [NCMPlaylist] = []

    // 扫码登录状态
    @Published var qrKey: String = ""
    @Published var qrImage: UIImage?
    @Published var qrMessage: String = ""
    @Published var qrBound: Bool = false

    var isLoggedIn: Bool { !token.isEmpty && user != nil }
    var displayName: String {
        if let n = ncmProfile?.nickname, !n.isEmpty { return n }
        if let n = user?.nickname, !n.isEmpty { return n }
        return "未登录"
    }

    // MARK: - 初始化刷新
    @MainActor
    func refresh() async {
        do {
            let s = try await APIClient.authStatus()
            status = s
            if let u = s.user, !token.isEmpty {
                user = u
            } else if !token.isEmpty {
                user = try? await APIClient.authMe()
                if user == nil { clearSession() }
            } else {
                user = nil
            }
        } catch {
            lastError = "账号服务不可用：\(error.localizedDescription)"
        }
        await refreshNCM()
    }

    // MARK: - 本地账号
    @MainActor
    func login(username: String, password: String) async -> Bool {
        lastError = nil
        do {
            let (t, u) = try await APIClient.authLogin(username: username, password: password)
            guard !t.isEmpty else { lastError = "登录失败：服务端未返回 token"; return false }
            applySession(t, u)
            return true
        } catch {
            lastError = "登录失败：\(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    func register(username: String, nickname: String, password: String) async -> Bool {
        lastError = nil
        do {
            let (t, u) = try await APIClient.authRegister(
                username: username, nickname: nickname, password: password)
            guard !t.isEmpty else { lastError = "注册失败：服务端未返回 token"; return false }
            applySession(t, u)
            return true
        } catch {
            lastError = "注册失败：\(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    private func applySession(_ t: String, _ u: KXUser?) {
        APIClient.token = t
        token = t
        user = u
        if u == nil { user = nil }   // 由 refresh 补拉
    }

    @MainActor
    func logout() async {
        try? await APIClient.authLogout()
        clearSession()
    }

    @MainActor
    private func clearSession() {
        APIClient.token = ""
        token = ""
        user = nil
        lastError = nil
    }

    @MainActor
    func updateProfile(nickname: String) async -> Bool {
        lastError = nil
        do {
            let u = try await APIClient.authUpdateProfile(nickname: nickname)
            user = u
            return true
        } catch {
            lastError = "修改失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 改密后服务端会吊销全部会话，返回 true 表示需要重新登录
    @MainActor
    func changePassword(old: String, new: String) async -> Bool {
        lastError = nil
        do {
            try await APIClient.authChangePassword(old: old, new: new)
            clearSession()
            return true
        } catch {
            lastError = "修改失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 网易云
    @MainActor
    func refreshNCM() async {
        do {
            let me = try await APIClient.ncmMe()
            ncmBound = me.bound
            ncmProfile = me.profile
            if me.bound { await loadNCMPlaylists() } else { ncmPlaylists = [] }
        } catch {
            ncmBound = false
            ncmProfile = nil
            ncmPlaylists = []
        }
    }

    @MainActor
    func loadNCMPlaylists() async {
        do { ncmPlaylists = try await APIClient.ncmPlaylists() }
        catch { lastError = "歌单拉取失败：\(error.localizedDescription)" }
    }

    @MainActor
    func unbindNCM() async {
        try? await APIClient.ncmUnbind()
        ncmBound = false
        ncmProfile = nil
        ncmPlaylists = []
    }

    // MARK: - 扫码登录
    @MainActor
    func startQR() async {
        qrBound = false
        qrImage = nil
        qrMessage = "正在获取二维码…"
        do {
            let key = try await APIClient.ncmQRKey()
            guard !key.isEmpty else { qrMessage = "获取二维码失败：unikey 为空"; return }
            let uri = try await APIClient.ncmQRCreate(key: key)
            qrKey = key
            qrImage = APIClient.imageFromDataURI(uri)
            qrMessage = qrImage == nil ? "二维码生成失败，请重试" : "请用网易云 App 扫码并确认"
        } catch {
            qrMessage = "二维码获取失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func pollQR() async {
        guard !qrKey.isEmpty, !qrBound else { return }
        do {
            let d = try await APIClient.ncmQRCheck(key: qrKey)
            if (d["bound"] as? Bool) == true {
                qrBound = true
                qrMessage = "登录成功"
                await refreshNCM()
                return
            }
            let code = d["code"] as? Int ?? 801
            switch code {
            case 800: qrMessage = "二维码已过期，请点击刷新"
            case 802: qrMessage = "已扫码，请在手机上确认登录"
            case 803: qrBound = true; qrMessage = "登录成功"; await refreshNCM()
            default:  qrMessage = "等待扫码…"
            }
        } catch {
            qrMessage = "状态查询失败：\(error.localizedDescription)"
        }
    }
}
