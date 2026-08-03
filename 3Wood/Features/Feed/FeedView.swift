import SwiftUI

struct FeedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigation.self) private var nav
    @State private var items: [FeedItem] = []
    @State private var unread = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var actionError: String?

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        @Bindable var router = nav.feedRouter
        NavigationStack(path: $router.path) {
            Group {
                if isLoading {
                    ProgressView()
                } else if loadFailed, items.isEmpty {
                    LoadFailedView { await reload() }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("Your feed is quiet", systemImage: "figure.golf")
                    } description: {
                        Text("Follow friends to see the courses they play and rank.")
                    } actions: {
                        NavigationLink("Find friends", value: Destination.findFriends)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List($items) { $item in
                        // Two tap targets per row (username → profile, rest →
                        // course), so navigation is gesture-driven rather than
                        // a NavigationLink — see FindFriendsView.
                        let openProfile: (() -> Void)? = item.actorID == myID ? nil : {
                            nav.feedRouter.push(.person(ProfileSummary(
                                id: item.actorID, username: item.username,
                                displayName: nil, isFollowing: false
                            )))
                        }
                        FeedRow(
                            item: $item,
                            onOpenProfile: openProfile,
                            onOpenCourse: { nav.feedRouter.push(.courseID(item.courseID)) },
                            onOpenActivity: { nav.feedRouter.push(.activity(item)) },
                            onReact: { emoji in await react(emoji, on: $item) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .creamScreen()
            .navigationTitle("3Wood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Wordmark(size: 24)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Destination.notifications) {
                        Image(systemName: unread > 0 ? "bell.badge.fill" : "bell")
                    }
                    .tint(Color.fairwayGreen)
                    .accessibilityLabel(unread > 0
                                        ? "Alerts, ^[\(unread) unread](inflect: true)"
                                        : "Alerts")
                    .accessibilityIdentifier("alertsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Destination.leaderboard) {
                        Image(systemName: "trophy")
                    }
                    .tint(Color.fairwayGreen)
                    .accessibilityLabel("Leaderboard")
                    .accessibilityIdentifier("leaderboardButton")
                }
            }
            .appDestinations()
            .task { await reload() }
            // The alert screen marks everything read; this clears the badge
            // without the two views knowing about each other.
            .onReceive(NotificationCenter.default.publisher(for: .unreadCountChanged)) { _ in
                Task { unread = (try? await ActivityRepo.unreadCount()) ?? 0 }
            }
            // Commenting or reacting on the detail screen changes counts the
            // feed is showing. Refetch just that row rather than the whole
            // feed, so scroll position and everything else stays put.
            .onReceive(NotificationCenter.default.publisher(for: .activityChanged)) { note in
                guard let id = note.object as? Int else { return }
                Task {
                    if let fresh = try? await ActivityRepo.activity(id: id),
                       let index = items.firstIndex(where: { $0.activityID == id }) {
                        items[index] = fresh
                    }
                }
            }
            .alert("Something went wrong", isPresented: .init(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
        .environment(router)
    }

    private func reload() async {
        do {
            items = try await FeedRepo.feed()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        unread = (try? await ActivityRepo.unreadCount()) ?? 0
        isLoading = false
    }

    /// Optimistic: the chip moves before the round trip, and rolls back if the
    /// write fails.
    private func react(_ emoji: String, on item: Binding<FeedItem>) async {
        let activityID = item.wrappedValue.activityID
        item.wrappedValue.applyToggle(emoji)
        do {
            try await ActivityRepo.toggleReaction(activityID: activityID, emoji: emoji)
        } catch {
            // Undo only this emoji. Restoring a whole snapshot would also wipe
            // a different reaction the user tapped while this call was still in
            // flight — and that one may have succeeded.
            item.wrappedValue.applyToggle(emoji)
            actionError = "Couldn't save that reaction. \(error.localizedDescription)"
        }
    }
}

private struct FeedRow: View {
    @Binding var item: FeedItem
    /// Opens the actor's profile; nil when the actor is you.
    let onOpenProfile: (() -> Void)?
    let onOpenCourse: () -> Void
    let onOpenActivity: () -> Void
    let onReact: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: item.isRanked ? "flag.checkered" : "bookmark.fill")
                    .foregroundStyle(item.isRanked ? Color.fairwayGreen : .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // e.g. "@mike ranked" / "@jenny wants to play"
                    if let onOpenProfile {
                        Button(action: onOpenProfile) {
                            actionLine
                        }
                        .buttonStyle(.borderless)
                        .tint(.primary)
                    } else {
                        actionLine
                    }
                    Text(item.courseName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(item.locationText) · \(item.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let partners = item.taggedUsernames, !partners.isEmpty {
                        Text("with \(partners.map { "@\($0)" }.formatted(.list(type: .and)))")
                            .font(.caption)
                            .foregroundStyle(Color.fairwayGreen)
                    }
                }
                Spacer()
                if item.isRanked {
                    ScoreBadge(score: item.score)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenCourse)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens course")
            .accessibilityAction(.default, onOpenCourse)
            .accessibilityActions {
                if let onOpenProfile {
                    Button("View @\(item.username)'s profile", action: onOpenProfile)
                }
                Button("Open comments", action: onOpenActivity)
            }

            engagementBar
        }
        .padding(.vertical, 2)
    }

    /// React without leaving the feed; comments are a push, since a thread
    /// needs the room.
    private var engagementBar: some View {
        HStack(spacing: 10) {
            ReactionBar(reactions: item.reactions, compact: true) { emoji in
                await onReact(emoji)
            }
            Button(action: onOpenActivity) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                    if item.commentCount > 0 {
                        Text("\(item.commentCount)").monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Color.sand, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.commentCount > 0
                                ? "^[\(item.commentCount) comment](inflect: true)"
                                : "Comment")
            Spacer()
        }
        .padding(.leading, 36)
    }

    private var actionLine: some View {
        (Text("@\(item.username) ").fontWeight(.semibold)
         + Text(item.isRanked ? "ranked" : "wants to play"))
            .font(.subheadline)
    }
}

#Preview {
    FeedView()
        .environment(SessionStore())
        .environment(AppNavigation())
}
