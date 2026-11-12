import DataKit
import Foundation

/// Stand-in when Supabase is not configured (fresh clone without `Secrets.xcconfig`): every action fails with
/// `AuthError.notConfigured`, which the sign-in screens show as a normal inline error.
struct NotConfiguredAuthService: AuthService {
    func restoreSession() async -> AuthState { .signedOut }
    func stateUpdates() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func signInWithApple() async throws -> AuthUser { throw AuthError.notConfigured }
    func signInWithGoogle() async throws -> AuthUser { throw AuthError.notConfigured }
    func signUp(email: String, password: String, locale: String?) async throws -> SignUpOutcome {
        throw AuthError.notConfigured
    }
    func signIn(email: String, password: String) async throws -> AuthUser { throw AuthError.notConfigured }
    func resendConfirmation(email: String) async throws { throw AuthError.notConfigured }
    func sendPasswordReset(email: String) async throws { throw AuthError.notConfigured }
    func updatePassword(_ newPassword: String) async throws { throw AuthError.notConfigured }
    func markOnboardingComplete() async throws { throw AuthError.notConfigured }
    func signOut() async {}
    func handle(url: URL) async -> Bool { false }
}
