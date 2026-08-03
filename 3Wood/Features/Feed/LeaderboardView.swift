import SwiftUI

struct LeaderboardView: View {
    @Environment(Router.self) private var router
    /// Rank roundel grows with the user's text size.
    @ScaledMetric(relativeTo: .body) private var medalSize: CGFloat = 36
    @State private var entries: [LeaderboardEntry] = []
    @State private var period: LeaderboardPeriod = .week
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            SegmentTabs(items: LeaderboardPeriod.allCases, title: \.rawValue, selection: $period)
            content
        }
        .creamScreen()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if loadFailed, entries.isEmpty {
                LoadFailedView { await reload() }
            } else if entries.isEmpty {
                // An empty week is normal on a Monday and means something very
                // different from an empty all-time board.
                switch period {
                case .week:
                    ContentUnavailableView(
                        "Nobody's logged a course yet this week",
                        systemImage: "calendar",
                        description: Text("Log one and you'll be top of the board.")
                    )
                case .allTime:
                    ContentUnavailableView("No rankings yet", systemImage: "trophy")
                }
            } else {
                List(entries) { entry in
                    HStack(spacing: 14) {
                        // Honor-board rank: brand numerals, a thin ring for
                        // the podium — flat, no trophy art.
                        ZStack {
                            if entry.rank <= 3 {
                                Circle()
                                    .strokeBorder(medalColor(entry.rank), lineWidth: 1.5)
                            }
                            Text("\(entry.rank)")
                                .font(.custom("Righteous-Regular", size: 17, relativeTo: .body))
                                .monospacedDigit()
                                .foregroundStyle(medalColor(entry.rank))
                        }
                        .frame(width: medalSize, height: medalSize)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(entry.username)")
                                .fontWeight(entry.isMe ? .bold : .regular)
                            if let name = entry.displayName {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("^[\(entry.played) course](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        // Your own row is not a link — nothing to follow — but
                        // the chevron still holds its space, or the trailing
                        // column steps 24pt left on that one row.
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .opacity(entry.isMe ? 0 : 1)
                            .accessibilityHidden(true)
                    }
                    .listRowBackground(entry.isMe ? Color.fairwayGreen.opacity(0.12) : Color.clear)
                    .listRowSeparatorTint(Color.sand)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !entry.isMe else { return }
                        router.push(.person(ProfileSummary(
                            id: entry.id, username: entry.username,
                            displayName: entry.displayName, isFollowing: false
                        )))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(entry.isMe ? [] : .isButton)
                    .accessibilityHint(entry.isMe ? "" : "Opens profile")
                    .accessibilityAction {
                        guard !entry.isMe else { return }
                        router.push(.person(ProfileSummary(
                            id: entry.id, username: entry.username,
                            displayName: entry.displayName, isFollowing: false
                        )))
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
    }

    private func reload() async {
        do {
            entries = try await FeedRepo.leaderboard(period: period)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: .medalGold
        case 2: .medalSilver
        case 3: .medalBronze
        default: .secondary
        }
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
        .environment(Router())
}
