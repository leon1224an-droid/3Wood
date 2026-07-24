import SwiftUI

struct FeedView: View {
    @Environment(SessionStore.self) private var session
    @State private var items: [FeedItem] = []
    @State private var selectedItem: FeedItem?
    @State private var selectedPerson: ProfileSummary?
    @State private var isLoading = true
    @State private var loadFailed = false

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        NavigationStack {
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
                        NavigationLink("Find friends") { FindFriendsView() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(items) { item in
                        // Two tap targets per row (username → profile, rest →
                        // course), so navigation is gesture-driven rather than
                        // a NavigationLink — see FindFriendsView.
                        let openProfile: (() -> Void)? = item.actorID == myID ? nil : {
                            selectedPerson = ProfileSummary(
                                id: item.actorID, username: item.username,
                                displayName: nil, isFollowing: false
                            )
                        }
                        FeedRow(item: item, onOpenProfile: openProfile)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedItem = item }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Opens course")
                            .accessibilityAction { selectedItem = item }
                            .accessibilityActions {
                                if let openProfile {
                                    Button("View @\(item.username)'s profile", action: openProfile)
                                }
                            }
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
                    NavigationLink {
                        LeaderboardView()
                    } label: {
                        Image(systemName: "trophy")
                    }
                    .tint(Color.fairwayGreen)
                    .accessibilityLabel("Leaderboard")
                    .accessibilityIdentifier("leaderboardButton")
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                CourseDetailByID(courseID: item.courseID)
            }
            .navigationDestination(item: $selectedPerson) { person in
                OtherProfileView(person: person)
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        do {
            items = try await FeedRepo.feed()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

private struct FeedRow: View {
    let item: FeedItem
    /// Opens the actor's profile; nil when the actor is you.
    let onOpenProfile: (() -> Void)?

    var body: some View {
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
        .padding(.vertical, 2)
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
}
