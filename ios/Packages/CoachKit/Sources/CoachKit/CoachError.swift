import Foundation

/// Everything that can go wrong talking to the coach, already mapped for the UI.
public enum CoachError: Error, Sendable, Equatable {
    /// The user has not agreed (to this version of) the AI data sharing consent; the app opens the consent screen.
    case consentRequired(requiredVersion: String?)
    /// Too many requests in a short time.
    case rateLimited(retryAt: Date?)
    /// The day's messages are used up.
    case quotaExceeded(resetAt: Date?, upgradeAvailable: Bool)
    /// The same message was just answered.
    case duplicateMessage
    /// The coach is switched off for today (spend cap) or the model is down.
    case unavailable
    /// The session is no longer valid even after a refresh.
    case unauthorized
    case offline
    case timeout
    case cancelled
    case invalidResponse
    case server(code: String, message: String)

    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .unavailable, .invalidResponse, .server, .rateLimited: true
        case .consentRequired, .quotaExceeded, .duplicateMessage, .unauthorized, .cancelled: false
        }
    }

    /// From an error body `{ "error": { "code", "message", "details" } }` and the HTTP status.
    public static func from(status: Int, body: Data) -> CoachError {
        let error = (try? JSONDecoder().decode(CoachJSON.self, from: body))?["error"]
        let code = error?["code"]?.string
        let details = error?["details"]
        let date = { (key: String) in details?[key]?.string.flatMap(CoachDates.parse) }
        switch (status, code) {
        case (_, "consent_required"): return .consentRequired(requiredVersion: details?["required_version"]?.string)
        case (_, "rate_limited"): return .rateLimited(retryAt: date("reset_at"))
        case (_, "quota_exceeded"):
            return .quotaExceeded(resetAt: date("reset_at"), upgradeAvailable: details?["upgrade_available"] == .bool(true))
        case (_, "duplicate_message"): return .duplicateMessage
        case (_, "coach_unavailable"): return .unavailable
        case (401, _), (_, "unauthorized"): return .unauthorized
        default: return .server(code: code ?? "http_\(status)", message: error?["message"]?.string ?? "")
        }
    }

    /// Any thrown error as a `CoachError`.
    public static func from(_ error: any Error) -> CoachError {
        if let coach = error as? CoachError { return coach }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost,
                .internationalRoamingOff:
                return .offline
            default: return .invalidResponse
            }
        }
        return .invalidResponse
    }
}
