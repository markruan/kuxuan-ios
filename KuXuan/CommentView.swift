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

    @State private var replyTo: KXComment?
    @State private var sendNotice: String?
    /// 分页哨兵按 offset 节流：List 复用会让 onAppear 反复触发，不该每次都新建一个请求 Task。
    @State private var lastSentinelOffset = -1

    private let pageSize = 20

    var body: some View {
        NavigationStack {
            Group {
                if loading && !loadedOnce {
                    KXCommentSkeleton()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            // 输入框状态收在独立子视图里：打字时只重算输入框，不再带着整个 List 的
            // 所有 cell 一起重算（旧版 draft 挂在 CommentSheet 上，每敲一个字都全量 diff）。
            .safeAreaInset(edge: .bottom) {
                CommentComposer(songID: songID,
                                replyTo: replyTo,
                                onCancelReply: { replyTo = nil },
                                onSent: { await load(reset: true) },
                                sendNotice: $sendNotice)
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
            .alert("评论", isPresented: Binding<Bool>(
                get: { sendNotice.map(KXNeedsAttention) ?? false },
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
                }
                Spacer()
            }
            .padding(.vertical, 10)
            // 只在「翻到新的一页」时换 id；旧版把 latest.count / moreError 也拼进 id，
            // 页内任意状态变化都会重建哨兵并重新触发 onAppear。
            .id("kx-page-\(offset)")
            .onAppear {
                guard lastSentinelOffset != offset else { return }
                lastSentinelOffset = offset
                Task { await loadMore() }
            }
        }
    }

    // 底部输入框拆成独立子视图 CommentComposer（文件末尾），避免打字重算整个 List。

    // MARK: 评论行（点回复图标进入回复态）
    @ViewBuilder
    private func commentRow(_ c: KXComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            KXAvatar(urlString: c.avatar, size: 34)

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
                        replyTo = c      // 输入框通过 onChange(of: replyTo?.id) 自己聚焦
                    } label: {
                        KXIcon(icon: .reply, size: 13, color: .secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回复 \(c.user)")
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
            lastSentinelOffset = -1
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

}

// MARK: - 独立评论输入框
/// 把 draft / sending / 焦点全部收在这个子视图里。
/// 旧版这些 @State 挂在 CommentSheet 上，每敲一个字符都会重算整个 body（含 List 的
/// ForEach 和所有评论行）；现在打字只影响这一小块，列表完全不参与 diff。
private struct CommentComposer: View {
    @EnvironmentObject var auth: AuthStore
    let songID: String
    let replyTo: KXComment?
    let onCancelReply: () -> Void
    let onSent: () async -> Void
    @Binding var sendNotice: String?

    @State private var draft = ""
    @State private var sending = false
    @FocusState private var composerFocused: Bool
    private let maxCommentLength = 140

    /// 与真正发送时的 trim 口径一致：140 个有效字 + 首尾空格不应被判超长
    private var draftCount: Int {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
    private var canSend: Bool {
        auth.ncmBound && !sending && !songID.isEmpty
            && draftCount > 0 && draftCount <= maxCommentLength
    }

    var body: some View {
        VStack(spacing: 0) {
            if let r = replyTo {
                HStack(spacing: 8) {
                    KXIcon(icon: .reply, size: 13, color: .kxAccent)
                    Text("回复 @\(r.user)：\(r.content)")
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    Button { onCancelReply() } label: {
                        KXIcon(icon: .close, size: 14, color: .secondary)
                            .contentShape(Rectangle().inset(by: -16))
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消回复")
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
                    Text("\(draftCount)/\(maxCommentLength)")
                        .font(.caption2)
                        .foregroundColor(draftCount > maxCommentLength ? .red : .secondary)
                }
                Button { Task { await send() } } label: {
                    if sending {
                        ProgressView().scaleEffect(0.85).frame(width: 28, height: 28)
                    } else {
                        KXIcon(icon: .send, size: 20,
                               color: canSend ? .kxAccent : .secondary)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("发送评论")
                .accessibilityHint(canSend ? "双击发送" : "当前无法发送")
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) { Divider() }
        .onChange(of: replyTo?.id) { id in
            if id != nil { composerFocused = true }
        }
    }

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
            onCancelReply()
            sendNotice = nil          // 成功不弹提示，输入框清空 + 列表刷新已是反馈
            await onSent()
        } catch {
            sendNotice = "发布失败：\(error.localizedDescription)"
        }
        sending = false
    }
}
