import SwiftUI

/// The alert feed: new followers, and reactions/comments on your activity.
struct NotificationsView: View {
    @Environment(Router.self) private var router
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
                                           ? Color.fairwayGreen.opacity(0.08)
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
        HStack(spacing: 12) {
            Group {
                switch item.kind {
                case "follow":
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Color.fairwayGreen)
                case "reaction":
                    Text(item.emoji ?? "👏")
                default:
                    Image(systemName: "bubble.left")
                        .foregroundStyle(Color.fairwayGreen)
                }
            }
            .frame(width: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(line(for: item))
                    .font(.subheadline)
                if let body = item.commentBody, item.kind == "comment" {
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
        let rest: String = switch item.kind {
        case "follow": "started following you"
        case "reaction": "reacted to your round at \(course)"
        default: "commented on your round at \(course)"
        }
        return actor + AttributedString(rest)
    }

    /// Follows open the person; engagement opens the activity it happened on.
    private func open(_ item: AppNotification) {
        if item.kind == "follow" || item.activityID == nil {
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
}
