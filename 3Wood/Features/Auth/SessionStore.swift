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
