import DataKit
import Foundation
import Observation
import StrengthKit

/// UI-facing score state (P064): the current overview of the preferred reference group, the bodyweight reminder and
/// the one-time model-change notice. The work happens in `ScoreService`; this only mirrors results for SwiftUI.
@MainActor
@Observable
final class ScoreCenter {
    private(set) var overview: ScoreOverview?
    private(set) var unavailable: ScoreUnavailable?
    private(set) var bodyweight: BodyweightStatus?
    private(set) var modelChange: ModelUpdater.Change?

    let service: ScoreService
    @ObservationIgnored private let updater: ModelUpdater?

    init(service: ScoreService, updater: ModelUpdater?) {
        self.service = service
        self.updater = updater
    }

    /// "Update your weight" is offered once the newest weigh-in is older than 60 days.
    var showsBodyweightReminder: Bool { bodyweight?.isStale == true }

    /// First start for a user: backfill weekly snapshots, then compute everything.
    func start(userId: UUID) async {
        await service.backfillIfNeeded(userId: userId)
        apply(await service.recalculate(userId: userId, trigger: .everything))
        await refreshSideState(userId: userId)
    }

    /// After a local change: recomputes only what changed (nothing when nothing score-relevant did).
    func refresh(userId: UUID) async {
        if let outcome = await service.refresh(userId: userId) { apply(outcome) }
        await refreshSideState(userId: userId)
    }

    func acknowledgeModelChange() {
        modelChange = nil
        Task { await updater?.acknowledgeChange() }
    }

    private func apply(_ outcome: ScoreOutcome) {
        switch outcome {
        case .ready(let value):
            overview = value
            unavailable = nil
        case .unavailable(let reason):
            unavailable = reason
        }
    }

    private func refreshSideState(userId: UUID) async {
        bodyweight = await service.bodyweight(userId: userId)
        modelChange = await updater?.pendingChange()
    }
}
