import DataKit

/// Adapts the `AuthService` to the root flow's `SessionService`.
struct AuthSessionService: SessionService {
    let auth: any AuthService

    func restoreSession() async throws -> SessionStatus {
        Self.status(for: await auth.restoreSession())
    }

    func updates() -> AsyncStream<SessionStatus> {
        let upstream = auth.stateUpdates()
        return AsyncStream { continuation in
            let task = Task {
                for await state in upstream { continuation.yield(Self.status(for: state)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signOut() async { await auth.signOut() }

    static func status(for state: AuthState) -> SessionStatus {
        switch state {
        case .signedOut: .signedOut
        // Recovery sessions are real sessions; the reset screen (P016) is shown by the auth UI, not the root.
        case .signedIn(let user), .passwordRecovery(let user): .signedIn(onboardingComplete: user.onboardingComplete)
        }
    }
}
