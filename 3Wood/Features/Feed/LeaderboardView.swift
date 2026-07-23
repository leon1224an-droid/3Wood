import SwiftUI

struct LeaderboardView: View {
    @State private var entries: [LeaderboardEntry] = []
    @State private var selectedPerson: ProfileSummary?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if entries.isEmpty {
                ContentUnavailableView("No rankings yet", systemImage: "trophy")
            } else {
                List(entries) { entry in
                    HStack(spacing: 14) {
                        Text("\(entry.rank)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(medalColor(entry.rank))
                            .frame(width: 32, alignment: .trailing)
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
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .listRowBackground(entry.isMe ? Color.fairwayGreen.opacity(0.12) : nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPerson = ProfileSummary(
                            id: entry.id, username: entry.username,
                            displayName: entry.displayName, isFollowing: false
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPerson) { person in
            OtherProfileView(person: person)
        }
        .task {
            entries = (try? await FeedRepo.leaderboard()) ?? []
            isLoading = false
        }
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.85, green: 0.65, blue: 0.13) // gold
        case 2: Color(red: 0.6, green: 0.6, blue: 0.62)   // silver
        case 3: Color(red: 0.72, green: 0.45, blue: 0.2)  // bronze
        default: .secondary
        }
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
}
