import SwiftUI

struct FeedView: View {
    @State private var items: [FeedItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false

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
                        NavigationLink(value: item) {
                            FeedRow(item: item)
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
            .navigationDestination(for: FeedItem.self) { item in
                CourseDetailByID(courseID: item.courseID)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isRanked ? "flag.checkered" : "bookmark.fill")
                .foregroundStyle(item.isRanked ? Color.fairwayGreen : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // e.g. "@mike ranked" / "@jenny wants to play"
                (Text("@\(item.username) ").fontWeight(.semibold)
                 + Text(item.isRanked ? "ranked" : "wants to play"))
                    .font(.subheadline)
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
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    FeedView()
}
