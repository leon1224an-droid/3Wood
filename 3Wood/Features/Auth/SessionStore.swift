import Foundation
import Supabase

/// Observes Supabase auth state and resolves it into what the UI needs:
/// signed out, signed in but missing a profile (first launch), or fully signed in.
@Observable
@MainActor
final class SessionStore {
    enum State {
        case loading
        case signedOut
        case needsProfile(userID: UUID)
        case signedIn(Profile)
        /// A session exists but the profile fetch failed (offline, backend
        /// blip). Never shown as signed-out — the user has an account.
        case failed(userID: UUID)
    }

    private(set) var state: State = .loading

    /// Set when the user arrives via a password-recovery deep link; RootView
    /// presents the new-password sheet while this is true.
    var needsPasswordReset = false

    /// Signed-out as a plain Bool, so RootView can observe the transition and
    /// clear navigation state that outlives the session.
    var isSignedOut: Bool {
        if case .signedOut = state { true } else { false }
    }

    /// Runs for the lifetime of the root view, reacting to every auth change.
    func start() async {
        for await (event, session) in supa.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .userUpdated:
                if let session {
                    await resolveProfile(userID: session.user.id)
                } else {
                    state = .signedOut
                }
            // Unreachable on this client, and deliberately kept anyway.
            // supabase-swift emits .passwordRecovery from one place only —
            // handleImplicitGrantFlow — and the client defaults to PKCE, so a
            // recovery link arrives as ?code=… and exchangeCodeForSession
            // emits .signedIn instead. RootView.openPasswordReset is what
            // actually raises the reset UI. This stays so the flow keeps
            // working if the client is ever switched to the implicit flow.
            case .passwordRecovery:
                needsPasswordReset = true
                if let session {
                    await resolveProfile(userID: session.user.id)
                }
            case .signedOut, .userDeleted:
                state = .signedOut
            default:
                break
            }
        }
    }

    /// Called by UsernameSetupView once the profile row exists.
    func profileCreated(_ profile: Profile) {
        state = .signedIn(profile)
    }

    /// Called after a recovery URL has established its session. This explicit
    /// signal also covers cold launches where the auth event arrives while the
    /// root auth gate is changing screens.
    func beginPasswordReset() {
        needsPasswordReset = true
    }

    /// Retry after a failed profile resolution (e.g. connectivity returned).
    func retryResolve() async {
        guard case .failed(let userID) = state else { return }
        state = .loading
        await resolveProfile(userID: userID)
    }

    func signOut() async {
        try? await supa.auth.signOut()
    }

    private func resolveProfile(userID: UUID) async {
        do {
            if let profile = try await ProfileRepo.fetch(userID: userID) {
                state = .signedIn(profile)
            } else {
                state = .needsProfile(userID: userID)
            }
        } catch {
            // Couldn't reach the backend. The session is still valid — surface
            // a retry screen rather than dumping the user on Welcome.
            state = .failed(userID: userID)
        }
    }
}
