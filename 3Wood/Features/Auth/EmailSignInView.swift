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
                    Text(errorMessage).foregroundStyle(.red)
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
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
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
