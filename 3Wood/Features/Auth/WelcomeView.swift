import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "figure.golf")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.fairwayGreen)
                Wordmark(size: 44)
                Text("Rank every course you've played.")
                    .foregroundStyle(.secondary)

                Spacer()

                // Sign in with Apple joins here in the App Store prep milestone,
                // once the Apple Developer account exists.
                NavigationLink("Create account") {
                    EmailSignInView(mode: .signUp)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                NavigationLink("Sign in") {
                    EmailSignInView(mode: .signIn)
                }
                .controlSize(.large)
            }
            .padding()
        }
    }
}

#Preview {
    WelcomeView()
}
