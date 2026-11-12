import Foundation

/// Where the user stands after the session has been restored.
enum SessionStatus: Sendable, Equatable {
    case signedOut
    case signedIn(onboardingComplete: Bool)
}

/// Source of truth for the auth session (production: `AuthSessionService` over the Supabase `AuthService`).
protocol SessionService: Sendable {
    func restoreSession() async throws -> SessionStatus
    /// Live changes after the restore (sign-in, sign-out, revoked session). Defaults to none.
    func updates() -> AsyncStream<SessionStatus>
    func signOut() async
    /// Persists that onboarding is finished, so a cold start goes straight to the app.
    func markOnboardingComplete() async
}

extension SessionService {
    func updates() -> AsyncStream<SessionStatus> { AsyncStream { $0.finish() } }
    func markOnboardingComplete() async {}
}

/// Fallback when the backend is not configured (see `AppContainer.live()`): always signed out.
struct PlaceholderSessionService: SessionService {
    func restoreSession() async throws -> SessionStatus { .signedOut }
    func signOut() async {}
}
