import Foundation
import Supabase

/// Supabase-backed `AuthService`. The session lives in the Keychain (SDK default `KeychainLocalStorage`);
/// the SDK refreshes tokens automatically. A failed refresh clears the session and emits `.signedOut`.
public final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient
    private let redirectURL: URL?
    private let apple: (any IDTokenProvider)?
    private let google: (any IDTokenProvider)?

    public init(
        client: SupabaseClient,
        redirectURL: URL? = nil,
        apple: (any IDTokenProvider)? = nil,
        google: (any IDTokenProvider)? = nil
    ) {
        self.client = client
        self.redirectURL = redirectURL
        self.apple = apple
        self.google = google
    }

    public convenience init(
        configuration: SupabaseConfiguration,
        apple: (any IDTokenProvider)? = nil,
        google: (any IDTokenProvider)? = nil
    ) {
        self.init(client: configuration.makeClient(), redirectURL: configuration.redirectURL, apple: apple, google: google)
    }

    // MARK: Session

    public func restoreSession() async -> AuthState {
        do {
            // Returns the stored session, refreshing it first when expired.
            let session = try await client.auth.session
            return .signedIn(Self.user(from: session.user))
        } catch {
            let mapped = AuthError.map(error)
            if mapped == .offline, let stored = client.auth.currentSession {
                // Offline start: keep the user in; the SDK retries the refresh later.
                return .signedIn(Self.user(from: stored.user))
            }
            if mapped != .sessionExpired && mapped != .offline {
                // Refresh was rejected for another reason: don't leave a dead session behind.
                try? await client.auth.signOut(scope: .local)
            }
            return .signedOut
        }
    }

    public func stateUpdates() -> AsyncStream<AuthState> {
        let upstream = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in upstream {
                    switch event {
                    case .signedOut, .userDeleted:
                        continuation.yield(.signedOut)
                    case .passwordRecovery:
                        if let session { continuation.yield(.passwordRecovery(Self.user(from: session.user))) }
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
                        if let session, !session.isExpired || event != .initialSession {
                            continuation.yield(.signedIn(Self.user(from: session.user)))
                        } else {
                            continuation.yield(.signedOut)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Sign in

    public func signInWithApple() async throws -> AuthUser {
        try await signInWithProvider(.apple, provider: apple)
    }

    public func signInWithGoogle() async throws -> AuthUser {
        try await signInWithProvider(.google, provider: google)
    }

    private func signInWithProvider(_ name: OpenIDConnectCredentials.Provider, provider: (any IDTokenProvider)?) async throws -> AuthUser {
        guard let provider else { throw AuthError.providerUnavailable }
        do {
            let credential = try await provider.credential()
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: name,
                    idToken: credential.idToken,
                    accessToken: credential.accessToken,
                    nonce: credential.nonce
                )
            )
            return Self.user(from: session.user)
        } catch {
            throw AuthError.map(error)
        }
    }

    public func signUp(email: String, password: String, locale: String?) async throws -> SignUpOutcome {
        do {
            let data: [String: AnyJSON]? = locale.map { ["locale": .string($0)] }
            let response = try await client.auth.signUp(
                email: email, password: password, data: data, redirectTo: redirectURL
            )
            switch response {
            case .session(let session):
                return .signedIn(Self.user(from: session.user))
            case .user(let user):
                // With confirmation on, GoTrue answers an existing address with a user that has no identities
                // (anti-enumeration). Report it as an already-registered address instead of a phantom pending sign-up.
                if user.identities?.isEmpty == true { throw AuthError.emailAlreadyRegistered }
                return .confirmationRequired(email: email)
            }
        } catch {
            throw AuthError.map(error)
        }
    }

    public func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return Self.user(from: session.user)
        } catch {
            throw AuthError.map(error)
        }
    }

    public func resendConfirmation(email: String) async throws {
        do {
            try await client.auth.resend(email: email, type: .signup, emailRedirectTo: redirectURL)
        } catch {
            throw AuthError.map(error)
        }
    }

    public func sendPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
        } catch {
            throw AuthError.map(error)
        }
    }

    public func updatePassword(_ newPassword: String) async throws {
        do {
            try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw AuthError.map(error)
        }
    }

    public func markOnboardingComplete() async throws {
        do {
            try await client.auth.update(user: UserAttributes(data: ["onboarding_complete": .bool(true)]))
        } catch {
            throw AuthError.map(error)
        }
    }

    public func signOut() async {
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // Offline or already invalid: make sure the local session is gone anyway.
            try? await client.auth.signOut(scope: .local)
        }
    }

    /// The current access token (refreshed first when it expired) for PostgREST and Edge Function calls (P045);
    /// nil when signed out or the refresh failed.
    public func accessToken() async -> String? {
        try? await client.auth.session.accessToken
    }

    /// Whether the signed-in account has a Sign in with Apple identity (account deletion must revoke its tokens).
    public func hasAppleIdentity() async -> Bool {
        guard let user = try? await client.auth.session.user else { return false }
        return user.identities?.contains { $0.provider == "apple" } ?? false
    }

    public func handle(url: URL) async -> Bool {
        guard let scheme = redirectURL?.scheme, url.scheme == scheme else { return false }
        do {
            _ = try await client.auth.session(from: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: Mapping

    static func user(from user: User) -> AuthUser {
        let onboarding: Bool
        if case .bool(let done)? = user.userMetadata["onboarding_complete"] { onboarding = done } else { onboarding = false }
        return AuthUser(
            id: user.id,
            email: user.email,
            isEmailConfirmed: user.emailConfirmedAt != nil,
            onboardingComplete: onboarding
        )
    }
}
