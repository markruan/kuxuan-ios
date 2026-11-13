import SwiftUI
import UIKit

// MARK: - 歌曲评论
// 读：后端 /api/online/comment/<id>（上游 /comment/music），滚到底自动翻页，无需点「加载更多」。
// 写：后端 /api/ncm/comment/add（上游 /comment，必须带已绑定的网易云 cookie）。
// 图标统一走 KXIcon（自绘），不使用苹果 SF Symbols。
struct CommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthStore
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
    @State private var reachedEnd = false
    @State private var noNewPages = 0
    @State private var moreError: String?

    @State private var draft = ""
    @State private var replyTo: KXComment?
    @State private var sending = false
    @State private var sendNotice: String?
    @FocusState private var composerFocused: Bool

    private let pageSize = 20
    private let maxCommentLength = 140

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
                        KXIcon(icon: .comment, size: 42, color: .secondary)
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
                                HStack(spacing: 6) {
                                    KXIcon(icon: .flame, size: 15, color: .kxAccent)
                                    Text("精彩评论")
                                }
                                .foregroundColor(.kxAccent)
                            }
                        }
                        Section {
                            ForEach(latest) { commentRow($0) }
                            paginationFooter
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
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle(songTitle.isEmpty ? "评论" : songTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load(reset: true) }
            .refreshable { await load(reset: true) }
            .alert("评论", isPresented: Binding<Bool>(
                get: { sendNotice != nil },
                set: { if !$0 { sendNotice = nil } }
            )) {
                Button("好", role: .cancel) { }
            } message: {
                Text(sendNotice ?? "")
            }
        }
    }

    // MARK: 自动分页哨兵
    /// 哨兵出现在可视区就请求下一页；每次翻页后 id 变化会重新触发 onAppear，
    /// 因此「一页填不满屏幕」时也能连续加载，直到被新内容推出视野或上游返回 more=false。
    /// 连续两页没有新增（去重后）就判为到底，避免上游异常导致无限请求。
    @ViewBuilder
    private var paginationFooter: some View {
        if more && !reachedEnd {
            HStack(spacing: 8) {
                Spacer()
                if moreError != nil {
                    Button {
                        moreError = nil
                        Task { await loadMore() }
                    } label: {
                        HStack(spacing: 6) {
                            KXIcon(icon: .refresh, size: 13, color: .kxAccent)
                            Text("加载失败，点此重试").font(.caption2)
                                .foregroundColor(.kxAccent)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView().scaleEffect(0.8)
                    Text("正在加载更多评论…")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .id("kx-page-\(offset)-\(latest.count)-\(moreError == nil)")
            .onAppear { Task { await loadMore() } }
        } else if loadedOnce && !latest.isEmpty {
            HStack {
                Spacer()
                Text("已经到底了 · 已加载 \(latest.count) 条")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: 底部评论输入框（发评论 / 回复）
    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            if let r = replyTo {
                HStack(spacing: 8) {
                    KXIcon(icon: .reply, size: 13, color: .kxAccent)
                    Text("回复 @\(r.user)：\(r.content)")
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    Button { replyTo = nil } label: {
                        KXIcon(icon: .close, size: 14, color: .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                TextField(auth.ncmBound
                          ? (replyTo == nil ? "写一条评论…" : "写回复…")
                          : "绑定网易云账号后可发评论",
                          text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                    .disabled(!auth.ncmBound)
                if !draft.isEmpty {
                    Text("\(draft.count)/\(maxCommentLength)")
                        .font(.caption2)
                        .foregroundColor(draft.count > maxCommentLength ? .red : .secondary)
                }
                Button { Task { await send() } } label: {
                    if sending {
                        ProgressView().scaleEffect(0.85).frame(width: 28, height: 28)
                    } else {
                        KXIcon(icon: .send, size: 20,
                               color: canSend ? .kxAccent : .secondary)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var canSend: Bool {
        auth.ncmBound && !sending && !songID.isEmpty
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= maxCommentLength
    }

    // MARK: 评论行（点回复图标进入回复态）
    @ViewBuilder
    private func commentRow(_ c: KXComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(LinearGradient.kxSoft)
                if !c.avatar.isEmpty {
                    AsyncImage(url: APIClient.proxiedPicURL(c.avatar, size: 80)) { phase in
                        if case .success(let im) = phase {
                            im.resizable().scaledToFill().clipShape(Circle())
                        }
                    }
                } else {
                    KXIcon(icon: .person, size: 18, color: .kxAccent)
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
                HStack(spacing: 6) {
                    Spacer()
                    Button {
                        replyTo = c
                        composerFocused = true
                    } label: {
                        KXIcon(icon: .reply, size: 13, color: .secondary)
                            .frame(width: 26, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    KXIcon(icon: .thumb, size: 13, color: .secondary)
                    Text(c.likedText).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: 加载
    @MainActor
    private func loadMore() async {
        guard loadedOnce, more, !reachedEnd, !loading, moreError == nil else { return }
        await load(reset: false)
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !songID.isEmpty else {
            errorMsg = "这首歌没有可用的网易云 ID，无法加载评论"
            return
        }
        if reset {
            offset = 0
            errorMsg = nil
            moreError = nil
            reachedEnd = false
            noNewPages = 0
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await APIClient.comments(songID: songID,
                                                 limit: pageSize, offset: offset)
            if reset {
                hot = r.hot
                latest = r.comments
                total = r.total
            } else {
                // 去重：上游翻页可能返回重复项
                let exist = Set(latest.map { $0.id })
                let fresh = r.comments.filter { !exist.contains($0.id) }
                latest.append(contentsOf: fresh)
                noNewPages = fresh.isEmpty ? noNewPages + 1 : 0
            }
            // offset 必须按「上游返回条数」前进，不能用去重后的条数，否则会卡在同一页
            offset += r.comments.count
            more = r.more && !r.comments.isEmpty
            if noNewPages >= 2 { reachedEnd = true }
            loadedOnce = true
            moreError = nil
            errorMsg = nil
        } catch {
            let msg = "评论加载失败：\(error.localizedDescription)"
            if reset {
                // 下拉刷新失败时保留已有列表，不要把整页变成错误页
                errorMsg = loadedOnce ? nil : msg
                moreError = loadedOnce ? msg : nil
            } else {
                moreError = msg
            }
        }
    }

    // MARK: 发送 / 回复（真实写入网易云账号）
    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard auth.ncmBound, !sending, !songID.isEmpty,
              !text.isEmpty, text.count <= maxCommentLength else { return }
        sending = true
        composerFocused = false
        do {
            try await APIClient.ncmSendComment(songID: songID, content: text,
                                               commentID: replyTo?.id)
            draft = ""
            replyTo = nil
            sendNotice = "评论已发布到网易云"
            await load(reset: true)
        } catch {
            sendNotice = "发布失败：\(error.localizedDescription)"
        }
        sending = false
    }
}
