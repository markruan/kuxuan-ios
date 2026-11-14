import SwiftUI

// 播放队列：从底部滑入的面板
struct QueueSheet: View {
    @EnvironmentObject var player: PlayerEngine
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { player.showQueue = false }
            VStack(spacing: 0) {
                // 自定义浮层也要有与系统 sheet 一致的关闭路径：指示条下滑 + 遮罩点击 + 完成按钮
                KXModalGrabber()
                    .kxModalDismiss(isPresented: Binding<Bool>(
                        get: { player.showQueue },
                        set: { player.showQueue = $0 }))
                HStack {
                    Text("播放列表").font(.headline)
                    Spacer()
                    Button("完成") { player.showQueue = false }
                        .foregroundColor(.kxAccent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("关闭播放列表")
                }
                .padding(16)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, s in
                                Button {
                                    player.playSongs(player.queue, index: i)
                                    player.showQueue = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(i + 1)").foregroundColor(.secondary)
                                            .frame(width: 28, alignment: .center)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.title).font(.subheadline).lineLimit(1)
                                            Text(s.artist).font(.caption)
                                                .foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if i == player.currentIndex {
                                            KXIcon(icon: .wave, size: 17, color: .kxAccent)
                                        }
                                    }
                                    .foregroundColor(i == player.currentIndex ? .kxAccent : .primary)
                                    .padding(10)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("播放第 \(i + 1) 首，\(s.title)，\(s.artist)")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 20)
                    }
                    .onAppear {
                        self.scrollCurrent(proxy)
                    }
                    .onChange(of: player.currentIndex) { _ in
                        self.scrollCurrent(proxy)
                    }
                }
            }
            .frame(height: UIScreen.main.bounds.height * 0.66)
            .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .ignoresSafeArea()
    }

    // ForEach 用的是歌曲 id（String），scrollTo 必须传同一个类型，
    // 之前传 Int 索引，滚动实际从未生效。
    private func scrollCurrent(_ proxy: ScrollViewProxy) {
        let i = player.currentIndex
        guard i >= 0, i < player.queue.count else { return }
        withAnimation { proxy.scrollTo(player.queue[i].id, anchor: .center) }
    }
}
