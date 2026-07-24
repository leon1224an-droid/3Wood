import SwiftUI
import Supabase

/// Presented after a password-recovery deep link: sets a new password on the
/// recovery session established by the link.
struct UpdatePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                } footer: {
                    Text("At least 6 characters.")
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
                            Text("Set new password")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isSubmitting || password.count < 6)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .creamScreen()
            .navigationTitle("New password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await supa.auth.update(user: UserAttributes(password: password))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    UpdatePasswordView()
}
