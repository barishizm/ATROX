import DataKit
import Foundation
import Observation

/// The user's AI-sharing decision (P081, App Store 5.1.2(i)). One instance per user is shared by the coach tab and
/// Settings, so withdrawing in Settings switches the coach off immediately.
@MainActor
@Observable
final class CoachConsentModel {
    enum State: Equatable {
        case loading
        /// Never answered, or answered for an older text: the consent screen is shown.
        case needed
        /// "Şimdi değil" or withdrawn: the coach tab explains and offers to review.
        case declined
        case granted
    }

    let userId: UUID
    private(set) var state: State = .loading
    private(set) var failed = false
    @ObservationIgnored private let service: ConsentService

    init(service: ConsentService, userId: UUID) {
        self.service = service
        self.userId = userId
    }

    var isGranted: Bool { state == .granted }

    func load() async {
        // A read error is treated as "ask": the coach must never run on an unknown consent.
        let status = (try? await service.aiSharingStatus(userId: userId)) ?? .notAsked
        state = Self.state(for: status)
    }

    func accept() async { await record(true) }

    /// "Şimdi değil" and "withdraw" are the same stored answer; the audit trail keeps every row.
    func decline() async { await record(false) }

    /// Re-opens the consent screen after a "not now".
    func reconsider() { if state == .declined { state = .needed } }

    private func record(_ granted: Bool) async {
        do {
            try await service.setAISharing(granted, userId: userId)
            failed = false
            state = granted ? .granted : .declined
        } catch {
            failed = true
        }
    }

    nonisolated static func state(for status: ConsentStatus) -> State {
        switch status {
        case .granted: .granted
        case .declined: .declined
        case .notAsked, .outdated: .needed
        }
    }
}

/// Coach switches kept on the device.
enum CoachPreferences {
    /// Proactive comments (workout summary, weekly summary). On by default; still needs the AI consent (P083).
    static let proactiveKey = "coach.proactive"
}
