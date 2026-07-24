import SwiftUI
import Supabase

/// Auth gate: routes between the sign-in flow, first-launch username setup,
/// and the main app based on session state.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                WelcomeView()
            case .needsProfile(let userID):
                UsernameSetupView(userID: userID)
            case .signedIn:
                MainTabView()
            case .failed:
                VStack(spacing: 24) {
                    Wordmark(size: 34)
                    LoadFailedView(message: "You're signed in, but we couldn't reach the server.") {
                        await session.retryResolve()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .creamScreen()
            }
        }
        .task {
            await session.start()
        }
        // Password-recovery links (threewood://reset-password#...) hand their
        // tokens to Supabase, which emits .passwordRecovery.
        .onOpenURL { url in
            Task { try? await supa.auth.session(from: url) }
        }
        .sheet(isPresented: $session.needsPasswordReset) {
            UpdatePasswordView()
        }
    }
}
