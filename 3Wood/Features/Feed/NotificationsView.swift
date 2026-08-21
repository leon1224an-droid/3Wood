import SwiftUI

/// The alert feed: new followers, and reactions/comments on your activity.
struct NotificationsView: View {
    @Environment(Router.self) private var router
    /// Grows with the user's text size — a fixed column clipped the emoji at
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .subheadline) private var iconColumn: CGFloat = 26
    @State private var items: [AppNotification] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if loadFailed, items.isEmpty {
                LoadFailedView { await reload() }
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "bell",
                    description: Text("Follows, reactions and comments on your rounds show up here.")
                )
            } else {
                List(items) { item in
                    row(item)
                        .listRowBackground(item.isUnread
                                           ? Color.sand.opacity(0.45)
                                           : Color.clear)
                        .listRowSeparatorTint(Color.sand)
                        .contentShape(Rectangle())
                        .onTapGesture { open(item) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { open(item) }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
        .creamScreen()
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            // Opening the screen is the read receipt. The rows keep their unread
            // tint for this viewing so it's clear what's new; the badge clears.
            try? await ActivityRepo.markAllRead()
            NotificationCenter.default.post(name: .unreadCountChanged, object: nil)
        }
    }

    private func row(_ item: AppNotification) -> some View {
        // Top-aligned: on two-line rows a centred icon floated between the
        // lines instead of sitting with the first one.
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch item.kind {
                case "follow":
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Color.fairwayGreen)
                case "reaction":
                    Text(item.emoji ?? "👏")
                case "tag":
                    Image(systemName: "person.2")
                        .foregroundStyle(Color.fairwayGreen)
                case "mention":
                    Image(systemName: "at")
                        .foregroundStyle(Color.fairwayGreen)
                case "list_like":
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.clayRed)
                case "list_comment":
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Color.fairwayGreen)
                default:
                    Image(systemName: "bubble.left")
                        .foregroundStyle(Color.fairwayGreen)
                }
            }
            .frame(width: iconColumn)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(line(for: item))
                    .font(.subheadline)
                if let body = item.commentBody, item.kind == "comment" || item.kind == "list_comment" {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func line(for item: AppNotification) -> AttributedString {
        var actor = AttributedString("@\(item.actorUsername) ")
        actor.font = .subheadline.weight(.semibold)
        let course = item.courseName ?? "your activity"
        let list = item.listTitle ?? "your list"
        let rest: String = switch item.kind {
        case "follow": "started following you"
        case "reaction": "reacted to your round at \(course)"
        case "tag": "tagged you at \(course)"
        case "mention": "mentioned you in a comment"
        case "list_like": "liked your list \"\(list)\""
        case "list_comment": "commented on your list \"\(list)\""
        default: "commented on your round at \(course)"
        }
        return actor + AttributedString(rest)
    }

    /// Follows open the person; engagement opens the activity or list it
    /// happened on. List notifications carry no activityID, so this check
    /// must come before the "activityID == nil" fallback below, or every
    /// list_like/list_comment would misroute to the actor's profile.
    private func open(_ item: AppNotification) {
        if let listID = item.listID {
            router.push(.listID(listID))
        } else if item.kind == "follow" || item.activityID == nil {
            router.push(.person(ProfileSummary(
                id: item.actorID, username: item.actorUsername,
                displayName: nil, isFollowing: false
            )))
        } else if let activityID = item.activityID {
            router.push(.activityID(activityID))
        }
    }

    private func reload() async {
        do {
            items = try await ActivityRepo.notifications()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

extension Notification.Name {
    /// Posted when the inbox is read, so the Feed's badge can refresh without
    /// the two screens holding a reference to each other.
    static let unreadCountChanged = Notification.Name("unreadCountChanged")

    /// Posted with an activity id when its comments or reactions change, so a
    /// feed row showing stale counts can refresh itself.
    static let activityChanged = Notification.Name("activityChanged")
}
