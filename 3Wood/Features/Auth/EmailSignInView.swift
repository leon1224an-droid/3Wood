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
    /// Kept separate from isSubmitting: that one drives the submit button's
    /// spinner, and sending a reset email should not make the *Sign in* button
    /// look like it is signing you in.
    @State private var isSendingReset = false
    @State private var resetNote: String?

    /// GoTrue matches on the exact string, so a trailing space from a paste or
    /// from autofill comes back as "Invalid login credentials" with nothing on
    /// screen to explain it. Normalise once, use everywhere.
    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

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

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode.title)
                    }
                }
                .buttonStyle(.primary)
                .disabled(isSubmitting || isSendingReset || normalizedEmail.isEmpty || password.count < 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task { await sendReset() }
                    }
                    .font(.subheadline)
                    .tint(Color.fairwayGreen)
                    .disabled(isSubmitting || isSendingReset)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
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
        let address = normalizedEmail
        guard !address.isEmpty else {
            resetNote = "Enter your email above first, then tap Forgot password."
            return
        }
        // Nothing used to guard this, so the .disabled() on the button was
        // never armed and repeat taps sent a reset each time — straight into
        // GoTrue's rate limiter, and into the SMTP hourly cap in production.
        isSendingReset = true
        defer { isSendingReset = false }
        do {
            try await supa.auth.resetPasswordForEmail(
                address,
                redirectTo: URL(string: "threewood://reset-password")
            )
            // "Open it on this device" is load-bearing: the PKCE code verifier
            // is stored locally by this install, so a link opened on another
            // device cannot complete the exchange.
            resetNote = "Check \(address) for a reset link. Open it on this device to set a new password."
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
                try await supa.auth.signUp(email: normalizedEmail, password: password)
            case .signIn:
                try await supa.auth.signIn(email: normalizedEmail, password: password)
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
