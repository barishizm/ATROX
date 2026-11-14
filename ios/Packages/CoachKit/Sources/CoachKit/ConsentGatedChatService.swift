import Foundation

/// Network-layer guarantee for App Store 5.1.2(i) (P081): without the user's current AI-sharing consent no request
/// reaches the coach endpoint. The check runs before every turn, so withdrawing the consent takes effect at once.
public struct ConsentGatedChatService: CoachChatService {
    public typealias Consent = @Sendable () async -> Bool

    private let base: any CoachChatService
    private let hasConsent: Consent
    private let requiredVersion: String?

    public init(_ base: any CoachChatService, requiredVersion: String? = nil, hasConsent: @escaping Consent) {
        self.base = base
        self.requiredVersion = requiredVersion
        self.hasConsent = hasConsent
    }

    public func stream(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard await hasConsent() else {
                    continuation.finish(throwing: CoachError.consentRequired(requiredVersion: requiredVersion))
                    return
                }
                do {
                    for try await event in base.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
