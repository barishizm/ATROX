import Foundation

/// Failures the UI can show. Every case has a localized, user-facing message (String Catalog in this package).
public enum AuthError: Error, Sendable, Equatable {
    case offline
    case invalidCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case weakPassword
    case rateLimited
    case cancelled
    case sessionExpired
    case providerUnavailable
    case notConfigured
    case unknown
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline: String(localized: "auth.error.offline", bundle: .module)
        case .invalidCredentials: String(localized: "auth.error.invalidCredentials", bundle: .module)
        case .emailNotConfirmed: String(localized: "auth.error.emailNotConfirmed", bundle: .module)
        case .emailAlreadyRegistered: String(localized: "auth.error.emailAlreadyRegistered", bundle: .module)
        case .weakPassword: String(localized: "auth.error.weakPassword", bundle: .module)
        case .rateLimited: String(localized: "auth.error.rateLimited", bundle: .module)
        case .cancelled: String(localized: "auth.error.cancelled", bundle: .module)
        case .sessionExpired: String(localized: "auth.error.sessionExpired", bundle: .module)
        case .providerUnavailable: String(localized: "auth.error.providerUnavailable", bundle: .module)
        case .notConfigured: String(localized: "auth.error.notConfigured", bundle: .module)
        case .unknown: String(localized: "auth.error.unknown", bundle: .module)
        }
    }
}
