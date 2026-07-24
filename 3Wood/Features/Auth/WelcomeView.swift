import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                // The wordmark IS the brand moment — no stock glyph above it.
                Wordmark(size: 56)
                Text("Rank every course you've played.")
                    .foregroundStyle(.secondary)

                Spacer()

                // Sign in with Apple joins here in the App Store prep milestone,
                // once the Apple Developer account exists.
                NavigationLink("Create account") {
                    EmailSignInView(mode: .signUp)
                }
                .buttonStyle(.primary)

                NavigationLink("Sign in") {
                    EmailSignInView(mode: .signIn)
                }
                .controlSize(.large)
                .tint(Color.fairwayGreen)
            }
            .padding()
            .creamScreen()
        }
    }
}

#Preview {
    WelcomeView()
}
