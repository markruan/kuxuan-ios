import SwiftUI
import UIKit

@main
struct KuXuanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerEngine()
    @StateObject private var auth = AuthStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(auth)
                .onAppear {
                    player.setup()
                    Task { await auth.refresh() }
                }
        }
    }
}

struct PlaylistRef: Identifiable, Hashable {
    let id: String
    let name: String
    let cover: String
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        // 先读出真实底部安全区，再让整个 ZStack 忽略底部安全区：
        // 迷你播放条因此能铺到屏幕物理底边，内容则靠 bottomInset 抬离 home indicator。
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                NavigationStack {
                    HomeView()
                        .navigationDestination(for: PlaylistRef.self) { ref in
                            PlaylistView(ref: ref)
                        }
                }

                if !player.queue.isEmpty {
                    MiniPlayer(bottomInset: geo.safeAreaInsets.bottom)
                        .zIndex(5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if player.showFullPlayer {
                    FullPlayer()
                        .zIndex(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 播放失败提示（版权/网络受限/上游 451）：全局浮层，迷你条与全屏页都可见
                if player.playError != nil {
                    PlayErrorToast()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, geo.safeAreaInsets.top + 14)
                        .zIndex(20)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            // transition 要由父级 animation 驱动；原先把 animation 挂在子视图上，
            // 全屏播放页与迷你条都是硬切出现/消失。
            .animation(.easeInOut(duration: 0.34), value: player.showFullPlayer)
            .animation(.easeInOut(duration: 0.28), value: player.queue.isEmpty)
        }
        // 从网易云 App 切回来时立刻核对服务端绑定态与二维码状态
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await auth.resumeQRCheck() } }
        }
    }
}

/// 方向锁：默认竖屏；进入全屏歌词时切横屏，返回时恢复竖屏。
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationMask
    }
}
