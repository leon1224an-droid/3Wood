import SwiftUI
import Supabase

/// Auth gate: routes between the sign-in flow, first-launch username setup,
/// and the main app based on session state.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigation.self) private var nav
    @State private var invitedPerson: ProfileSummary?
    @State private var resetLinkError: String?
    @State private var didSetNewPassword = false

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
        // Reaching this sheet means a recovery link already established a real
        // session. Dismissing it without setting a password would leave someone
        // signed in to an account they still don't have a password for — and
        // with no route back, since the link is single-use. So back out of the
        // session unless the password was actually changed.
        .sheet(isPresented: $session.needsPasswordReset) {
            if !didSetNewPassword {
                Task { await session.signOut() }
            }
            didSetNewPassword = false
        } content: {
            UpdatePasswordView(didSetPassword: $didSetNewPassword)
        }
        .onChange(of: session.isSignedOut) { _, signedOut in
            if signedOut { nav.reset() }
        }
        // Shown over Welcome, after the sign-out that deletion triggers. The
        // deletion is already done by the time this appears — this is an
        // acknowledgement, not a last chance to back out.
        .alert("Account deleted", isPresented: $session.didDeleteAccount) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your profile, rankings, and lists have been permanently removed.")
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
            // The reset UI has to be raised explicitly here — waiting on the
            // .passwordRecovery auth event does not work. supabase-swift emits
            // that event only from handleImplicitGrantFlow, and this client is
            // on the default PKCE flow, so the link arrives as ?code=… and
            // exchangeCodeForSession emits a bare .signedIn. Relying on the
            // event is what made the reset screen never appear at all.
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
