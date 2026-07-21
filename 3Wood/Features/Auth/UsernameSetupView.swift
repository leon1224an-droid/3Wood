import SwiftUI

/// First-launch step after signup: pick a unique username, which creates the
/// profiles row.
struct UsernameSetupView: View {
    let userID: UUID
    @Environment(SessionStore.self) private var session

    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var isValid: Bool {
        username.wholeMatch(of: /[a-z0-9_]{3,20}/) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Choose a username")
                } footer: {
                    Text("3–20 characters: lowercase letters, numbers, underscores.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Let's golf").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || !isValid)
            }
            .navigationTitle("Welcome!")
        }
    }

    private func submit() async {
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
