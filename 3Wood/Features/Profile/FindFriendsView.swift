import SwiftUI

struct FindFriendsView: View {
    @State private var query = ""
    @State private var results: [ProfileSummary] = []
    @State private var selectedPerson: ProfileSummary?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        // The row carries two independent tap targets (open profile / follow),
        // so navigation is driven by an explicit tap gesture rather than a
        // NavigationLink nested beside the button — the latter makes row taps
        // unreliable in SwiftUI lists.
        List($results) { $person in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(person.username)")
                    if let name = person.displayName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                FollowButton(person: $person)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedPerson = person }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search by username")
        .onChange(of: query) {
            scheduleSearch()
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView(
                    "Find friends",
                    systemImage: "person.2",
                    description: Text("See how your friends rate the courses you've played.")
                )
            }
        }
        .navigationTitle("Find friends")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPerson) { person in
            OtherProfileView(person: person)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = (try? await SocialRepo.searchProfiles(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            results = found
        }
    }
}

struct FollowButton: View {
    @Binding var person: ProfileSummary

    var body: some View {
        Button(person.isFollowing ? "Following" : "Follow") {
            Task {
                do {
                    if person.isFollowing {
                        try await SocialRepo.unfollow(userID: person.id)
                    } else {
                        try await SocialRepo.follow(userID: person.id)
                    }
                    person.isFollowing.toggle()
                } catch {
                    // State unchanged on failure; next search reflects reality.
                }
            }
        }
        .buttonStyle(.borderless)
        .tint(person.isFollowing ? .secondary : Color.fairwayGreen)
        .controlSize(.small)
    }
}
