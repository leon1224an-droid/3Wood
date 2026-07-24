import SwiftUI
import Supabase

struct EmailSignInView: View {
    enum Mode {
        case signIn, signUp

        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .signUp: "Create account"
            }
        }
    }

    let mode: Mode
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var resetNote: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            } footer: {
                if mode == .signUp {
                    Text("At least 6 characters.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Color.clayRed)
                }
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(mode.title).frame(maxWidth: .infinity)
                }
            }
            .disabled(isSubmitting || email.isEmpty || password.count < 6)

            if mode == .signIn {
                Button("Forgot password?") {
                    Task { await sendReset() }
                }
                .font(.subheadline)
                .tint(Color.fairwayGreen)
                .disabled(isSubmitting)
            }
        }
        .creamScreen()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password reset", isPresented: .init(
            get: { resetNote != nil },
            set: { if !$0 { resetNote = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetNote ?? "")
        }
    }

    private func sendReset() async {
        guard !email.isEmpty else {
            resetNote = "Enter your email above first, then tap Forgot password."
            return
        }
        do {
            try await supa.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "threewood://reset-password")
            )
            resetNote = "Check \(email) for a reset link. Open it on this device to set a new password."
        } catch {
            resetNote = "Couldn't send the reset email. \(error.localizedDescription)"
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .signUp:
                try await supa.auth.signUp(email: email, password: password)
            case .signIn:
                try await supa.auth.signIn(email: email, password: password)
            }
            // SessionStore reacts to the auth state change; nothing else to do.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        EmailSignInView(mode: .signUp)
    }
}
