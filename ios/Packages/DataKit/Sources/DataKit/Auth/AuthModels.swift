import Foundation

/// The signed-in user, reduced to what the app needs. No tokens leave the service.
public struct AuthUser: Sendable, Equatable, Hashable {
    public let id: UUID
    public let email: String?
    public let isEmailConfirmed: Bool
    /// Interim flag until the profile table exists (P018+); read from `user_metadata.onboarding_complete`.
    public let onboardingComplete: Bool

    public init(id: UUID, email: String?, isEmailConfirmed: Bool, onboardingComplete: Bool = false) {
        self.id = id
        self.email = email
        self.isEmailConfirmed = isEmailConfirmed
        self.onboardingComplete = onboardingComplete
    }
}

/// Auth state as seen by the app.
public enum AuthState: Sendable, Equatable {
    case signedOut
    case signedIn(AuthUser)
    /// The user opened a password-reset link; a new password must be set.
    case passwordRecovery(AuthUser)
}

/// Result of an e-mail sign-up.
public enum SignUpOutcome: Sendable, Equatable {
    /// Confirmation is disabled for this project: the user is signed in right away.
    case signedIn(AuthUser)
    /// A confirmation e-mail was sent; sign-in is blocked until the link is opened.
    case confirmationRequired(email: String)
}

/// An OpenID Connect identity token from a native provider flow.
public struct IDTokenCredential: Sendable, Equatable {
    public let idToken: String
    public let accessToken: String?
    /// The raw (un-hashed) nonce that was bound to the token, if any.
    public let nonce: String?

    public init(idToken: String, accessToken: String? = nil, nonce: String? = nil) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.nonce = nonce
    }
}

/// Runs the native Apple/Google flow and returns the token. Implemented in the app target (needs UI).
public protocol IDTokenProvider: Sendable {
    func credential() async throws -> IDTokenCredential
}
