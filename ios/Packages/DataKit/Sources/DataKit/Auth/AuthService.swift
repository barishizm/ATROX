import Foundation

/// Identity layer used by the whole app. Implementations: `SupabaseAuthService` (production),
/// `FakeAuthService` (tests, previews). All failures are thrown as `AuthError`.
public protocol AuthService: Sendable {
    /// Current state, restoring the persisted session (refreshing it if expired).
    /// A session that can no longer be refreshed is cleared and reported as `.signedOut`.
    func restoreSession() async -> AuthState

    /// Live state changes (sign in, sign out, password recovery, remote revocation). Emits the current state first.
    func stateUpdates() -> AsyncStream<AuthState>

    func signInWithApple() async throws -> AuthUser
    func signInWithGoogle() async throws -> AuthUser
    func signUp(email: String, password: String, locale: String?) async throws -> SignUpOutcome
    func signIn(email: String, password: String) async throws -> AuthUser
    func resendConfirmation(email: String) async throws
    func sendPasswordReset(email: String) async throws
    func updatePassword(_ newPassword: String) async throws
    func signOut() async

    /// Records on the server (`user_metadata.onboarding_complete`) that the signed-in user finished onboarding.
    func markOnboardingComplete() async throws

    /// Hands a `vesania://auth-callback…` link (email confirmation / password reset) to the SDK.
    /// Returns false when the URL is not an auth link.
    func handle(url: URL) async -> Bool
}
