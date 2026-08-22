import SwiftUI

/// Flat-plus-one-level comment thread: top-level comments, each followed by
/// its own replies (indented, one level only). Shared by ActivityDetailView
/// and ListDetailView — activity_comments and list_comments are deliberately
/// identical in shape (parent_comment_id, reactions) so this same view
/// renders both without knowing which backs it.
struct CommentThreadView: View {
    let comments: [ActivityComment]
    let onReact: (ActivityComment, String) async -> Void
    let onReply: (ActivityComment) -> Void
    let onDelete: (ActivityComment) -> Void
    let onReport: (ActivityComment) -> Void
    let onTapUser: (ActivityComment) -> Void

    private var topLevel: [ActivityComment] {
        comments.filter { $0.parentCommentID == nil }
    }

    private func replies(to id: Int) -> [ActivityComment] {
        comments.filter { $0.parentCommentID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(topLevel) { comment in
                VStack(alignment: .leading, spacing: 10) {
                    row(comment)
                    ForEach(replies(to: comment.id)) { reply in
                        row(reply)
                            .padding(.leading, 28)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ comment: ActivityComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if comment.isMine {
                    Text("@\(comment.username)").font(.subheadline.weight(.semibold))
                } else {
                    Button {
                        onTapUser(comment)
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
                // Visible, not long-press-only — matches the reasoning already
                // documented on this screen's report/delete menu.
                Menu {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") {
                        onReply(comment)
                    }
                    if comment.isMine {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            onDelete(comment)
                        }
                    } else {
                        Button("Report comment", systemImage: "flag") {
                            onReport(comment)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Comment actions")
            }
            Text(comment.body).font(.subheadline)
            ReactionBar(reactions: comment.reactions, compact: true) { emoji in
                await onReact(comment, emoji)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
        .contextMenu {
            Button("Reply", systemImage: "arrowshape.turn.up.left") {
                onReply(comment)
            }
            if comment.isMine {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete(comment)
                }
            } else {
                Button("Report comment", systemImage: "flag") {
                    onReport(comment)
                }
            }
        }
    }
}
