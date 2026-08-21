import SwiftUI

/// First-launch step after signup: pick a unique username, which creates the
/// profiles row.
struct UsernameSetupView: View {
    let userID: UUID
    @Environment(SessionStore.self) private var session

    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var isValid: Bool { Username.isValid(username) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .onChange(of: username) {
                            let cleaned = Username.sanitize(username)
                            if cleaned != username { username = cleaned }
                        }
                } header: {
                    Text("Choose a username")
                } footer: {
                    Text("3–20 characters: letters, numbers, underscores.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.clayRed)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Let's golf")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isSubmitting || !isValid)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .creamScreen()
            .navigationTitle("Welcome!")
            // Without this there is no way off this screen. It is the root of
            // the auth gate whenever a session has no profiles row, so it has
            // no back button — and a recovery deep link can land you here on an
            // account you never finished setting up, with picking a username
            // the only way forward. Signing out has to be reachable.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") {
                        Task { await session.signOut() }
                    }
                    .tint(Color.fairwayGreen)
                }
            }
        }
    }

    private func submit() async {
        guard !ContentFilter.isObjectionable(username) else {
            errorMessage = "That username isn't allowed. Please choose another."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let profile = try await ProfileRepo.create(userID: userID, username: username)
            session.profileCreated(profile)
        } catch {
            let text = error.localizedDescription
            errorMessage = text.contains("duplicate") || text.contains("unique")
                ? "That username is taken — try another."
                : text
        }
    }
}
