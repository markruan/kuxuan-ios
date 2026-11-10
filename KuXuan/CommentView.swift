import SwiftUI

// MARK: - 歌曲评论
// 数据来自新增的后端代理 /api/online/comment/<song.file>，
// 上游是 3100 的 /comment/music；只读，单机版没有发评论/点赞能力。
struct CommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let songID: String
    let songTitle: String

    @State private var hot: [KXComment] = []
    @State private var latest: [KXComment] = []
    @State private var total = 0
    @State private var more = false
    @State private var offset = 0
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var loadedOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && !loadedOnce {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载评论…").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let e = errorMsg, !loadedOnce {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                            .font(.largeTitle).foregroundColor(.secondary)
                        Text(e).font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await load(reset: true) } }
                            .buttonStyle(.borderedProminent).tint(.kxAccent)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !hot.isEmpty {
                            Section {
                                ForEach(hot) { commentRow($0) }
                            } header: {
                                Label("精彩评论", systemImage: "flame.fill")
                                    .foregroundColor(.kxAccent)
                            }
                        }
                        Section {
                            ForEach(latest) { commentRow($0) }
                            if more {
                                HStack {
                                    Spacer()
                                    if loading { ProgressView() }
                                    else {
                                        Button("加载更多评论") { Task { await load(reset: false) } }
                                            .font(.footnote).tint(.kxAccent)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            if latest.isEmpty && hot.isEmpty {
                                Text("这首歌还没有评论").font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text("最新评论 · 共 \(total) 条")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(songTitle.isEmpty ? "评论" : songTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load(reset: true) }
            .refreshable { await load(reset: true) }
        }
    }

    @ViewBuilder
    private func commentRow(_ c: KXComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(LinearGradient.kxSoft)
                if !c.avatar.isEmpty {
                    AsyncImage(url: APIClient.proxiedPicURL(c.avatar)) { phase in
                        if case .success(let im) = phase {
                            im.resizable().scaledToFill().clipShape(Circle())
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .font(.caption).foregroundColor(.kxAccent)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(c.user).font(.caption.bold()).lineLimit(1)
                    Spacer()
                    if !c.displayTime.isEmpty {
                        Text(c.displayTime).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(c.content).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if !c.quote.isEmpty {
                    Text(c.quote)
                        .font(.caption).foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemFill))
                        .cornerRadius(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Label(c.likedText, systemImage: "hand.thumbsup")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load(reset: Bool) async {
        guard !songID.isEmpty else {
            errorMsg = "这首歌没有可用的网易云 ID，无法加载评论"
            return
        }
        if reset { offset = 0; errorMsg = nil }
        guard !loading else { return }
        loading = true
        do {
            let r = try await APIClient.comments(songID: songID, limit: 20, offset: offset)
            if reset {
                hot = r.hot
                latest = r.comments
                total = r.total
            } else {
                // 去重：上游翻页可能返回重复项
                let exist = Set(latest.map { $0.id })
                latest.append(contentsOf: r.comments.filter { !exist.contains($0.id) })
            }
            more = r.more
            offset += r.comments.count
            loadedOnce = true
        } catch {
            errorMsg = "评论加载失败：\(error.localizedDescription)\n请确认 Mac 上 server.py 已重启并包含新端点"
            if !loadedOnce { loadedOnce = false }
        }
        loading = false
    }
}
