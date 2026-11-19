import DataKit
import Foundation
import Observation

/// The user's decision to let meal photos and descriptions go to the AI provider (App Store 5.1.2(i)). A separate
/// consent from the coach's, because the data is different (photos).
@MainActor
@Observable
final class FoodConsentModel {
    enum State: Equatable { case loading, needed, declined, granted }

    let userId: UUID
    private(set) var state: State = .loading
    private(set) var failed = false
    @ObservationIgnored private let service: ConsentService
    @ObservationIgnored private let upload: (@Sendable (_ userId: UUID, _ version: String) async -> Bool)?

    init(service: ConsentService, userId: UUID, upload: (@Sendable (_ userId: UUID, _ version: String) async -> Bool)? = nil) {
        self.service = service
        self.userId = userId
        self.upload = upload
    }

    var isGranted: Bool { state == .granted }

    func load() async {
        let status = (try? await service.foodAISharingStatus(userId: userId)) ?? .notAsked
        state = Self.state(for: status)
    }

    func accept() async { await record(true) }
    func decline() async { await record(false) }

    private func record(_ granted: Bool) async {
        do {
            try await service.setFoodAISharing(granted, userId: userId)
            if granted, let upload { _ = await upload(userId, ConsentVersions.current.foodAISharing) }
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
