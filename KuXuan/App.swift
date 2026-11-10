import SwiftUI

@main
struct KuXuanApp: App {
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
    @EnvironmentObject var player: PlayerEngine
    var body: some View {
        ZStack {
            NavigationStack {
                HomeView()
                    .navigationDestination(for: PlaylistRef.self) { ref in
                        PlaylistView(ref: ref)
                    }
            }

            VStack {
                Spacer()
                if !player.queue.isEmpty {
                    MiniPlayer()
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }

            if player.showFullPlayer {
                FullPlayer()
                    .zIndex(10)
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut(duration: 0.32), value: player.showFullPlayer)
            }
        }
    }
}
