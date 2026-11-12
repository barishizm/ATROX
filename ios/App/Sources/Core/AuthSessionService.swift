import DataKit

/// Adapts the `AuthService` to the root flow's `SessionService`.
struct AuthSessionService: SessionService {
    let auth: any AuthService
    var completion: any OnboardingCompletionStore = UserDefaultsOnboardingCompletionStore()

    func restoreSession() async throws -> SessionStatus {
        await resolve(await auth.restoreSession())
    }

    func updates() -> AsyncStream<SessionStatus> {
        let upstream = auth.stateUpdates()
        return AsyncStream { continuation in
            let task = Task {
                for await state in upstream { continuation.yield(await resolve(state)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signOut() async { await auth.signOut() }

    func markOnboardingComplete() async {
        guard let user = Self.user(in: await auth.restoreSession()) else { return }
        completion.markComplete(userId: user.id)
        do {
            try await auth.markOnboardingComplete()
        } catch {
            // Kept locally; `resolve` retries the server write on the next launch.
            Log.app.error("Could not store onboarding completion on the server: \(error)")
        }
    }

    /// The server flag or the on-device record, whichever says "done". A local-only flag is pushed to the server.
    private func resolve(_ state: AuthState) async -> SessionStatus {
        guard let user = Self.user(in: state), !user.onboardingComplete, completion.isComplete(userId: user.id) else {
            return Self.status(for: state)
        }
        try? await auth.markOnboardingComplete()
        return .signedIn(onboardingComplete: true)
    }

    private static func user(in state: AuthState) -> AuthUser? {
        switch state {
        case .signedIn(let user), .passwordRecovery(let user): user
        case .signedOut: nil
        }
    }

    static func status(for state: AuthState) -> SessionStatus {
        switch state {
        case .signedOut: .signedOut
        // Recovery sessions are real sessions; the reset screen (P016) is shown by the auth UI, not the root.
        case .signedIn(let user), .passwordRecovery(let user): .signedIn(onboardingComplete: user.onboardingComplete)
        }
    }
}
