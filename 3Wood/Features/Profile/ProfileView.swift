import SwiftUI
import Supabase

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigation.self) private var nav
    @State private var stats: ProfileStats?
    @State private var wantToPlayCount: Int?
    @State private var peopleMode: PeopleListView.Mode?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var myID: UUID? {
        if case .signedIn(let profile) = session.state { return profile.id }
        return nil
    }

    var body: some View {
        NavigationStack {
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
                            // Buttons + navigationDestination (not NavigationLink)
                            // so the List doesn't bolt a chevron onto each chip.
                            HStack(spacing: 10) {
                                Button {
                                    peopleMode = .followers
                                } label: {
                                    followChip(count: stats?.followers, label: "Followers")
                                }
                                .buttonStyle(.plain)
                                Button {
                                    peopleMode = .following
                                } label: {
                                    followChip(count: stats?.following, label: "Following")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .task {
                        stats = try? await SocialRepo.stats(of: profile.id)
                        wantToPlayCount = (try? await WantToPlayRepo.list())?.count
                    }
                }

                Section {
                    listLink("Courses played", count: stats?.played, segment: .played)
                    listLink("Want to play", count: wantToPlayCount, segment: .wantToPlay)
                }

                Section {
                    NavigationLink {
                        FindFriendsView()
                    } label: {
                        Label("Find friends", systemImage: "person.badge.plus")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
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
            .navigationDestination(item: $peopleMode) { mode in
                if let myID {
                    PeopleListView(userID: myID, mode: mode)
                }
            }
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
    }

    /// Flat capsule stat button: bold count + label, ruled in sand.
    private func followChip(count: Int?, label: String) -> some View {
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

    private func deleteAccount() async {
        do {
            try await supa.rpc("delete_account").execute()
            try? await supa.auth.signOut(scope: .local)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
