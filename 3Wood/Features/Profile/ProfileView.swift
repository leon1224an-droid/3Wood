import SwiftUI
import Supabase

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var stats: ProfileStats?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                if case .signedIn(let profile) = session.state {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName ?? profile.username)
                                .font(.title2.bold())
                            Text("@\(profile.username)")
                                .foregroundStyle(.secondary)
                            if let stats {
                                Text("\(stats.played) played · \(stats.followers) followers · \(stats.following) following")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .task {
                        stats = try? await SocialRepo.stats(of: profile.id)
                    }
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
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                    Button("Delete account", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .navigationTitle("Profile")
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

    private func deleteAccount() async {
        do {
            try await supa.rpc("delete_account").execute()
            try? await supa.auth.signOut(scope: .local)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
