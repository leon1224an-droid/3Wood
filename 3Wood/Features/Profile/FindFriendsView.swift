import SwiftUI

struct FindFriendsView: View {
    @Environment(Router.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var query = ""
    @State private var results: [ProfileSummary] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchFailed = false

    private var myUsername: String? {
        if case .signedIn(let profile) = session.state { return profile.username }
        return nil
    }

    var body: some View {
        List {
            Section {
                Button {
                    router.push(.contacts)
                } label: {
                    HStack {
                        Label("Find from contacts", systemImage: "person.crop.circle.badge.plus")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ShareLink(
                    item: Invite.link(from: myUsername),
                    message: Text(Invite.message(from: myUsername))
                ) {
                    Label("Invite friends", systemImage: "paperplane")
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("Search by username, or match your contacts to see how your friends rate the courses you've played.")
            }

            if searchFailed, results.isEmpty {
                Section {
                    LoadFailedView { scheduleSearch() }
                        .listRowBackground(Color.clear)
                }
            } else if !results.isEmpty {
                // Each row carries two independent tap targets (open profile /
                // follow), so navigation is driven by an explicit tap gesture
                // rather than a NavigationLink nested beside the button — the
                // latter makes row taps unreliable in SwiftUI lists.
                Section("Results") {
                    ForEach($results) { $person in
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
                        .onTapGesture { router.push(.person(person)) }
                        .personRowAccessibility(person: $person) { router.push(.person(person)) }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.sand)
                    }
                }
            } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                Section {
                    Text("No one matched \"\(query)\".")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .creamScreen()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by username")
        .keepsBackButtonDuringSearch()
        .onChange(of: query) {
            scheduleSearch()
        }
        .navigationTitle("Find friends")
        .navigationBarTitleDisplayMode(.inline)
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
            do {
                let found = try await SocialRepo.searchProfiles(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                searchFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchFailed = true
            }
        }
    }
}

extension View {
    /// Keeps the navigation bar's back button on screen while the search
    /// field is focused. By default a focused search field takes over the
    /// bar, leaving only a dismiss-search "✕" — which is why testers reported
    /// no way back out of the find-friends flow. Deployment target is 17.0,
    /// so the modifier is guarded; on 17.0 the behaviour is unchanged.
    @ViewBuilder
    func keepsBackButtonDuringSearch() -> some View {
        if #available(iOS 17.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }

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
