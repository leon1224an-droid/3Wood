import SwiftUI
import Supabase

/// Auth gate: routes between the sign-in flow, first-launch username setup,
/// and the main app based on session state.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var invitedPerson: ProfileSummary?

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
        // threewood://invite?ref=<username> opens the inviter's profile;
        // anything else (threewood://reset-password#...) hands its tokens to
        // Supabase, which emits .passwordRecovery.
        .onOpenURL { url in
            if url.scheme == "threewood", url.host == "invite" {
                let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "ref" }?.value
                if let ref {
                    Task { await openInvite(ref: ref) }
                }
            } else {
                Task { try? await supa.auth.session(from: url) }
            }
        }
        .sheet(isPresented: $session.needsPasswordReset) {
            UpdatePasswordView()
        }
        .sheet(item: $invitedPerson) { person in
            InviteProfileSheet(person: person)
        }
    }

    private func openInvite(ref: String) async {
        guard case .signedIn = session.state else { return }
        let found = (try? await SocialRepo.searchProfiles(ref)) ?? []
        invitedPerson = found.first { $0.username == ref.lowercased() }
    }
}

/// Deep-link destination: a self-contained stack with its own router so the
/// invited-to profile (and anything pushed from it) works outside the tabs.
private struct InviteProfileSheet: View {
    let person: ProfileSummary
    @State private var router = Router()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            OtherProfileView(person: person)
                .appDestinations()
        }
        .environment(router)
    }
}
