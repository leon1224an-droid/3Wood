import SwiftUI
import Supabase

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigation.self) private var nav
    @State private var stats: ProfileStats?
    @State private var wantToPlayCount: Int?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        @Bindable var router = nav.profileRouter
        NavigationStack(path: $router.path) {
            List {
                if case .signedIn(let profile) = session.state {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? profile.username)
                                    .font(.title2.bold())
                                Text("@\(profile.username)")
                                    .foregroundStyle(.secondary)
                            }
                            // Buttons + router push (not NavigationLink) so
                            // the List doesn't bolt a chevron onto each chip.
                            HStack(spacing: 10) {
                                Button {
                                    nav.profileRouter.push(.people(userID: profile.id, mode: .followers))
                                } label: {
                                    FollowChip(count: stats?.followers, label: "Followers")
                                }
                                .buttonStyle(.plain)
                                Button {
                                    nav.profileRouter.push(.people(userID: profile.id, mode: .following))
                                } label: {
                                    FollowChip(count: stats?.following, label: "Following")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    listLink("Courses played", count: stats?.played, segment: .played)
                    listLink("Want to play", count: wantToPlayCount, segment: .wantToPlay)
                }

                Section {
                    NavigationLink(value: Destination.findFriends) {
                        Label("Find friends", systemImage: "person.badge.plus")
                    }
                    NavigationLink(value: Destination.about) {
                        Label("About", systemImage: "info.circle")
                    }
                }

                Section {
                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .foregroundStyle(Color.clayRed)
                    Button("Delete account") {
                        isConfirmingDelete = true
                    }
                    .foregroundStyle(Color.clayRed)
                }
            }
            .creamScreen()
            .navigationTitle("Profile")
            // Counts go stale while the tab stays mounted — reload whenever the
            // screen comes back into view (tab switch or popping a child).
            .onAppear { Task { await reloadCounts() } }
            .refreshable { await reloadCounts() }
            .appDestinations()
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently removes your profile, rankings, and lists. It cannot be undone.")
            }
            .alert("Couldn't delete account", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
        .environment(router)
    }

    /// Row that jumps to the Lists tab on the given segment.
    private func listLink(_ title: String, count: Int?, segment: ListsView.Segment) -> some View {
        Button {
            nav.showLists(segment)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reloadCounts() async {
        guard let myID else { return }
        stats = try? await SocialRepo.stats(of: myID)
        wantToPlayCount = (try? await WantToPlayRepo.list())?.count
    }

    private func deleteAccount() async {
        do {
            try await supa.rpc("delete_account").execute()
            try? await supa.auth.signOut(scope: .local)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
