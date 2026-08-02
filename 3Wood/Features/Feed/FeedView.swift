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

    /// Optimistic: the emoji lands before the round trip, and rolls back if
    /// the write fails.
    private func react(_ emoji: String, on item: Binding<FeedItem>) async {
        let previous = item.wrappedValue.myReaction
        let previousCount = item.wrappedValue.reactionCount
        if previous == emoji {
            item.wrappedValue.myReaction = nil
            item.wrappedValue.reactionCount = max(0, previousCount - 1)
        } else {
            if previous == nil { item.wrappedValue.reactionCount = previousCount + 1 }
            item.wrappedValue.myReaction = emoji
        }
        do {
            try await ActivityRepo.toggleReaction(
                activityID: item.wrappedValue.activityID, emoji: emoji
            )
        } catch {
            item.wrappedValue.myReaction = previous
            item.wrappedValue.reactionCount = previousCount
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
        HStack(spacing: 14) {
            Menu {
                ForEach(Reaction.all, id: \.self) { emoji in
                    Button {
                        Task { await onReact(emoji) }
                    } label: {
                        Text("\(emoji)  \(Reaction.label(for: emoji))")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let mine = item.myReaction {
                        Text(mine)
                    } else {
                        Image(systemName: "face.smiling")
                    }
                    if item.reactionCount > 0 {
                        Text("\(item.reactionCount)").monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(item.myReaction == nil ? Color.secondary : Color.fairwayGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(item.myReaction == nil
                                   ? Color.clear
                                   : Color.fairwayGreen.opacity(0.12))
                )
                .overlay(Capsule().strokeBorder(Color.sand, lineWidth: 1))
            }
            .accessibilityLabel(item.myReaction == nil
                                ? "React"
                                : "Your reaction: \(Reaction.label(for: item.myReaction ?? ""))")

            Button(action: onOpenActivity) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                    if item.commentCount > 0 {
                        Text("\(item.commentCount)").monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Color.sand, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.commentCount > 0
                                ? "^[\(item.commentCount) comment](inflect: true)"
                                : "Comment")

            // Who else reacted, at a glance.
            if let emojis = item.topEmojis, !emojis.isEmpty {
                Text(emojis.joined())
                    .font(.subheadline)
                    .accessibilityHidden(true)
            }
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
