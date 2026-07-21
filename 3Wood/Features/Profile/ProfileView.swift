import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

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
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
