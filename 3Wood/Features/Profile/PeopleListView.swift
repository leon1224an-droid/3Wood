import SwiftUI

/// Flat capsule stat chip: bold count + label, ruled in sand. Shared by the
/// own-profile and other-profile headers so the two screens stay in step.
struct FollowChip: View {
    let count: Int?
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count ?? 0)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.darkPine)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.cream, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.sand, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A followers/following list. Each row opens that user's profile; the follow
/// button is hidden for your own row.
struct PeopleListView: View {
    enum Mode: Identifiable {
        case followers, following
        var id: Self { self }
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
    @Environment(Router.self) private var router
    @State private var people: [ProfileSummary] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if loadFailed, people.isEmpty {
                LoadFailedView { await reload() }
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
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.push(.person(person)) }
                    .personRowAccessibility(person: $person) { router.push(.person(person)) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.sand)
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
        .creamScreen()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        do {
            people = mode == .followers
                ? try await SocialRepo.followers(of: userID)
                : try await SocialRepo.following(of: userID)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
