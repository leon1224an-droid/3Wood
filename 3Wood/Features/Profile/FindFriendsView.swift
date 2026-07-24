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
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedPerson = person }
            .personRowAccessibility(person: $person) { selectedPerson = person }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.sand)
        }
        .listStyle(.plain)
        .creamScreen()
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

extension View {
    /// VoiceOver support for people rows that navigate via a tap gesture:
    /// exposes the row as one button that opens the profile, with
    /// follow/unfollow as a custom action.
    func personRowAccessibility(
        person: Binding<ProfileSummary>, open: @escaping () -> Void
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens profile")
            .accessibilityAction { open() }
            .accessibilityAction(named: person.wrappedValue.isFollowing ? "Unfollow" : "Follow") {
                Task {
                    let p = person.wrappedValue
                    do {
                        if p.isFollowing {
                            try await SocialRepo.unfollow(userID: p.id)
                        } else {
                            try await SocialRepo.follow(userID: p.id)
                        }
                        person.wrappedValue.isFollowing.toggle()
                    } catch {}
                }
            }
    }
}

struct FollowButton: View {
    @Binding var person: ProfileSummary
    @State private var failed = false

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
                    failed = true
                }
            }
        }
        .buttonStyle(.borderless)
        .tint(person.isFollowing ? .secondary : Color.fairwayGreen)
        .controlSize(.small)
        .alert("Couldn't update follow", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }
}
