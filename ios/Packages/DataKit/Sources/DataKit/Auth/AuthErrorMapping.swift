import AuthenticationServices
import Foundation
import Supabase

extension AuthError {
    /// Maps any error thrown by the SDK, the system or a provider flow to an `AuthError`.
    public static func map(_ error: any Error) -> AuthError {
        if let known = error as? AuthError { return known }
        if error is CancellationError { return .cancelled }

        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return .cancelled
            default: return .offline
            }
        }

        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain {
            switch ASAuthorizationError.Code(rawValue: ns.code) {
            case .canceled: return .cancelled
            case .notHandled, .failed, .invalidResponse, .unknown, .notInteractive: return .providerUnavailable
            default: return .providerUnavailable
            }
        }
        // GoogleSignIn: domain "com.google.GIDSignIn", code -5 = canceled by user.
        if ns.domain == "com.google.GIDSignIn" {
            return ns.code == -5 ? .cancelled : .providerUnavailable
        }

        if let auth = error as? Supabase.AuthError {
            return map(auth)
        }
        return .unknown
    }

    private static func map(_ error: Supabase.AuthError) -> AuthError {
        switch error {
        case .sessionMissing, .refreshDiscarded:
            return .sessionExpired
        case .weakPassword:
            return .weakPassword
        case .api(_, let code, _, let response):
            switch code {
            case .invalidCredentials: return .invalidCredentials
            case .emailNotConfirmed, .providerEmailNeedsVerification: return .emailNotConfirmed
            case .emailExists, .userAlreadyExists: return .emailAlreadyRegistered
            case .weakPassword: return .weakPassword
            case .overRequestRateLimit, .overEmailSendRateLimit, .overSMSSendRateLimit: return .rateLimited
            case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed, .badJWT:
                return .sessionExpired
            case .signupDisabled, .providerDisabled, .emailProviderDisabled, .oauthProviderNotSupported:
                return .providerUnavailable
            default:
                if response.statusCode == 429 { return .rateLimited }
                return .unknown
            }
        default:
            return .unknown
        }
    }
}
