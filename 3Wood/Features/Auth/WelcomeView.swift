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

                Text("By continuing you agree to the [Terms](https://leon1224an-droid.github.io/3Wood/terms.html) and [Privacy Policy](https://leon1224an-droid.github.io/3Wood/privacy.html).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .tint(Color.fairwayGreen)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding()
            .creamScreen()
        }
    }
}

#Preview {
    WelcomeView()
}
