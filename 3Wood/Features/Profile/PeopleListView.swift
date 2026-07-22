import SwiftUI

/// Tappable played/followers/following counts. Followers and following push a
/// PeopleListView. Requires an enclosing NavigationStack.
struct ProfileStatsBar: View {
    let userID: UUID
    let stats: ProfileStats

    var body: some View {
        HStack(spacing: 28) {
            StatItem(value: stats.played, label: "Played")
            NavigationLink {
                PeopleListView(userID: userID, mode: .followers)
            } label: {
                StatItem(value: stats.followers, label: "Followers")
            }
            .buttonStyle(.plain)
            NavigationLink {
                PeopleListView(userID: userID, mode: .following)
            } label: {
                StatItem(value: stats.following, label: "Following")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StatItem: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A followers/following list. Each row opens that user's profile; the follow
/// button is hidden for your own row.
struct PeopleListView: View {
    enum Mode {
        case followers, following
        var title: String {
            switch self {
            case .followers: "Followers"
            case .following: "Following"
            }
        }
    }

    let userID: UUID
    let mode: Mode

    @Environment(SessionStore.self) private var session
    @State private var people: [ProfileSummary] = []
    @State private var selectedPerson: ProfileSummary?
    @State private var isLoading = true

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if people.isEmpty {
                ContentUnavailableView(
                    mode == .followers ? "No followers yet" : "Not following anyone yet",
                    systemImage: "person.2"
                )
            } else {
                List($people) { $person in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(person.username)")
                            if let name = person.displayName {
                                Text(name).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if person.id != myID {
                            FollowButton(person: $person)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPerson = person }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPerson) { person in
            OtherProfileView(person: person)
        }
        .task {
            do {
                people = mode == .followers
                    ? try await SocialRepo.followers(of: userID)
                    : try await SocialRepo.following(of: userID)
            } catch {
                people = []
            }
            isLoading = false
        }
    }
}
