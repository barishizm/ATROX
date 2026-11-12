import Foundation

/// In-memory `AuthService` for tests and previews. Behaviour is scripted through the stored closures/results.
public actor FakeAuthService: AuthService {
    public struct Account: Sendable {
        public var password: String
        public var confirmed: Bool
        public var user: AuthUser
    }

    private var state: AuthState
    private var accounts: [String: Account] = [:]
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    /// Set to make the next call fail with this error (consumed once).
    public var nextError: AuthError?
    /// Whether sign-up needs e-mail confirmation.
    public var requiresConfirmation = true
    public private(set) var passwordResetRequests: [String] = []
    public private(set) var signOutCount = 0
    public var appleUser = AuthUser(id: UUID(), email: "apple@example.com", isEmailConfirmed: true)
    public var googleUser = AuthUser(id: UUID(), email: "google@example.com", isEmailConfirmed: true)

    public init(initial: AuthState = .signedOut) {
        state = initial
    }

    public func setNextError(_ error: AuthError?) { nextError = error }
    public func setRequiresConfirmation(_ value: Bool) { requiresConfirmation = value }

    /// Marks the account's e-mail as confirmed (simulates the user opening the link).
    public func confirm(email: String) {
        accounts[email]?.confirmed = true
    }

    /// Simulates a server-side revocation / failed refresh.
    public func simulateRemoteSignOut() { publish(.signedOut) }

    // MARK: AuthService

    public func restoreSession() async -> AuthState { state }

    public nonisolated func stateUpdates() -> AsyncStream<AuthState> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id: id) } }
        }
    }

    public func signInWithApple() async throws -> AuthUser {
        try failIfScripted()
        publish(.signedIn(appleUser))
        return appleUser
    }

    public func signInWithGoogle() async throws -> AuthUser {
        try failIfScripted()
        publish(.signedIn(googleUser))
        return googleUser
    }

    public func signUp(email: String, password: String, locale: String?) async throws -> SignUpOutcome {
        try failIfScripted()
        guard accounts[email] == nil else { throw AuthError.emailAlreadyRegistered }
        guard password.count >= 8 else { throw AuthError.weakPassword }
        let user = AuthUser(id: UUID(), email: email, isEmailConfirmed: !requiresConfirmation)
        accounts[email] = Account(password: password, confirmed: !requiresConfirmation, user: user)
        if requiresConfirmation { return .confirmationRequired(email: email) }
        publish(.signedIn(user))
        return .signedIn(user)
    }

    public func signIn(email: String, password: String) async throws -> AuthUser {
        try failIfScripted()
        guard let account = accounts[email], account.password == password else { throw AuthError.invalidCredentials }
        guard account.confirmed else { throw AuthError.emailNotConfirmed }
        publish(.signedIn(account.user))
        return account.user
    }

    public func resendConfirmation(email: String) async throws { try failIfScripted() }

    public func sendPasswordReset(email: String) async throws {
        try failIfScripted()
        passwordResetRequests.append(email)
    }

    public func updatePassword(_ newPassword: String) async throws {
        try failIfScripted()
        guard newPassword.count >= 8 else { throw AuthError.weakPassword }
    }

    public func signOut() async {
        signOutCount += 1
        publish(.signedOut)
    }

    public func handle(url: URL) async -> Bool { url.scheme == "atrox" }

    // MARK: Internals

    private func register(id: UUID, continuation: AsyncStream<AuthState>.Continuation) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) { continuations[id] = nil }

    private func publish(_ new: AuthState) {
        state = new
        for continuation in continuations.values { continuation.yield(new) }
    }

    private func failIfScripted() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}
