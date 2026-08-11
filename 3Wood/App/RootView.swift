import SwiftUI
import Supabase

/// Auth gate: routes between the sign-in flow, first-launch username setup,
/// and the main app based on session state.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var invitedPerson: ProfileSummary?
    @State private var resetLinkError: String?

    var body: some View {
        @Bindable var session = session
        // Keep a stable container around the auth gate. A Group is transparent,
        // so changing branches can cancel and restart the auth-listener task.
        ZStack {
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
        .onOpenURL { url in
            if url.scheme == "threewood", url.host == "invite" {
                let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "ref" }?.value
                if let ref {
                    Task { await openInvite(ref: ref) }
                }
            } else if url.scheme == "threewood", url.host == "reset-password" {
                Task { await openPasswordReset(url) }
            }
        }
        .sheet(isPresented: $session.needsPasswordReset) {
            UpdatePasswordView()
        }
        .sheet(item: $invitedPerson) { person in
            InviteProfileSheet(person: person)
        }
        .alert("Password reset link", isPresented: .init(
            get: { resetLinkError != nil },
            set: { if !$0 { resetLinkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetLinkError ?? "")
        }
    }

    private func openPasswordReset(_ url: URL) async {
        do {
            // session(from:) emits .signedIn before .passwordRecovery. Set the
            // recovery UI explicitly as well, so a cold-launch listener cannot
            // miss the second event while the auth gate changes screens.
            try await supa.auth.session(from: url)
            session.beginPasswordReset()
        } catch {
            resetLinkError = "This reset link is invalid or expired. Request a new one and try again."
        }
    }

    private func openInvite(ref: String) async {
        guard case .signedIn = session.state else { return }
        let found = (try? await SocialRepo.searchProfiles(ref)) ?? []
        invitedPerson = found.first { $0.username.caseInsensitiveCompare(ref) == .orderedSame }
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
