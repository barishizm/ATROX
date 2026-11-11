import Foundation

/// Where the user stands after the session has been restored.
enum SessionStatus: Sendable, Equatable {
    case signedOut
    case signedIn(onboardingComplete: Bool)
}

/// Source of truth for the auth session. The real Supabase-backed one arrives with P015.
protocol SessionService: Sendable {
    func restoreSession() async throws -> SessionStatus
    func signOut() async
}

/// Used until real auth exists: always starts signed out.
struct PlaceholderSessionService: SessionService {
    func restoreSession() async throws -> SessionStatus { .signedOut }
    func signOut() async {}
}
