import SwiftUI

/// One feed activity with its reactions and comment thread.
struct ActivityDetailView: View {
    let item: FeedItem

    @Environment(Router.self) private var router
    @State private var reaction: String?
    @State private var reactionCount: Int
    @State private var comments: [ActivityComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSending = false
    @State private var actionError: String?
    @State private var reportedComment: ActivityComment?
    @FocusState private var composerFocused: Bool

    init(item: FeedItem) {
        self.item = item
        _reaction = State(initialValue: item.myReaction)
        _reactionCount = State(initialValue: item.reactionCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    reactionBar
                    Divider().overlay(Color.sand)
                    commentsSection
                }
                .padding()
            }
            composer
        }
        .creamScreen()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Something went wrong", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog(
            "Report @\(reportedComment?.username ?? "")'s comment?",
            isPresented: .init(
                get: { reportedComment != nil },
                set: { if !$0 { reportedComment = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    if let comment = reportedComment {
                        Task { await report(comment, reason: reason) }
                    }
                }
            }
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.isRanked ? "flag.checkered" : "bookmark.fill")
                    .foregroundStyle(item.isRanked ? Color.fairwayGreen : .secondary)
                    .accessibilityHidden(true)
                (Text("@\(item.username) ").fontWeight(.semibold)
                 + Text(item.isRanked ? "ranked" : "wants to play"))
                    .font(.subheadline)
                Spacer()
                if item.isRanked {
                    ScoreBadge(score: item.score)
                }
            }
            Button {
                router.push(.courseID(item.courseID))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.courseName)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(item.locationText) · \(item.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the course")
        }
        .padding()
        .card()
    }

    /// The full palette, always visible — picking a reaction shouldn't need a
    /// long-press to discover.
    private var reactionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Reaction.all, id: \.self) { emoji in
                    Button {
                        Task { await toggle(emoji) }
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(reaction == emoji
                                              ? Color.fairwayGreen.opacity(0.18)
                                              : Color.clear)
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    reaction == emoji ? Color.fairwayGreen : Color.sand,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Reaction.label(for: emoji))
                    .accessibilityAddTraits(reaction == emoji ? [.isButton, .isSelected] : .isButton)
                }
            }
            if reactionCount > 0 {
                Text("^[\(reactionCount) reaction](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if loadFailed, comments.isEmpty {
            LoadFailedView { await reload() }
        } else if comments.isEmpty {
            Text("No comments yet. Say something.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if comment.isMine {
                                Text("@\(comment.username)")
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                Button {
                                    router.push(.person(ProfileSummary(
                                        id: comment.userID, username: comment.username,
                                        displayName: nil, isFollowing: false
                                    )))
                                } label: {
                                    Text("@\(comment.username)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens profile")
                            }
                            Spacer()
                            Text(comment.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(comment.body).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .card()
                    .contextMenu {
                        if comment.isMine {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await delete(comment) }
                            }
                        } else {
                            Button("Report comment", systemImage: "flag") {
                                reportedComment = comment
                            }
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.sand).frame(height: 1)
            HStack(spacing: 10) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(trimmedDraft.isEmpty || isSending)
                .tint(Color.fairwayGreen)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.cream)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reload() async {
        do {
            comments = try await ActivityRepo.comments(activityID: item.activityID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func toggle(_ emoji: String) async {
        // Move first; the row is tiny and waiting on the network to light up
        // makes the whole bar feel broken.
        let previous = reaction
        let previousCount = reactionCount
        if reaction == emoji {
            reaction = nil
            reactionCount = max(0, reactionCount - 1)
        } else {
            if reaction == nil { reactionCount += 1 }
            reaction = emoji
        }
        do {
            try await ActivityRepo.toggleReaction(activityID: item.activityID, emoji: emoji)
        } catch {
            reaction = previous
            reactionCount = previousCount
            actionError = "Couldn't save that reaction. \(error.localizedDescription)"
        }
    }

    private func send() async {
        let body = trimmedDraft
        guard !body.isEmpty else { return }
        isSending = true
        do {
            try await ActivityRepo.addComment(activityID: item.activityID, body: body)
            draft = ""
            composerFocused = false
            await reload()
        } catch {
            actionError = "Couldn't post that comment. \(error.localizedDescription)"
        }
        isSending = false
    }

    private func delete(_ comment: ActivityComment) async {
        do {
            try await ActivityRepo.deleteComment(id: comment.id)
            await reload()
        } catch {
            actionError = "Couldn't delete that comment. \(error.localizedDescription)"
        }
    }

    private func report(_ comment: ActivityComment, reason: ReportReason) async {
        do {
            try await ModerationRepo.report(
                userID: comment.userID, commentID: comment.id, reason: reason.rawValue
            )
            actionError = "Report received. We review reports within 24 hours."
        } catch {
            actionError = "Couldn't send the report. \(error.localizedDescription)"
        }
    }
}
