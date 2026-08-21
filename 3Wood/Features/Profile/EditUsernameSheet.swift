import SwiftUI

/// Rename the account's @username. Same rules as first-launch setup;
/// uniqueness is case-insensitive server-side.
struct EditUsernameSheet: View {
    let profile: Profile

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(profile: Profile) {
        self.profile = profile
        _username = State(initialValue: profile.username)
    }

    private var canSave: Bool {
        Username.isValid(username) && username != profile.username && !isSaving
    }

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
                    Text("Username")
                } footer: {
                    Text("3–20 characters: letters, numbers, underscores. Your rankings, reviews, and followers stay with you; your old username becomes available to others.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.clayRed)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save username")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSave)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .creamScreen()
            .navigationTitle("Change username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard !ContentFilter.isObjectionable(username) else {
            errorMessage = "That username isn't allowed. Please choose another."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await ProfileRepo.updateUsername(userID: profile.id, username: username)
            session.profileCreated(updated)
            dismiss()
        } catch {
            let text = error.localizedDescription
            errorMessage = text.contains("duplicate") || text.contains("unique")
                ? "That username is taken — try another."
                : text
        }
    }
}
