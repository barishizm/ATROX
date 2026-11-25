import DataKit
import Foundation

/// What the Profile sync card says for a coordinator state (P045). Pure, so it is unit-tested.
enum SyncStatusPresenter {
    enum Headline: Equatable {
        case syncing
        case restoring(done: Int, total: Int)
        case upToDate
        case pending(Int)
        case offline
        case failed
    }

    enum Tone: Equatable { case normal, warning, error }

    static func headline(phase: SyncCoordinator.Phase, pending: Int) -> Headline {
        switch phase {
        case .syncing: .syncing
        case .restoring(let progress): .restoring(done: progress.done, total: progress.total)
        case .waitingToRetry: .offline
        case .failed: .failed
        case .idle: pending > 0 ? .pending(pending) : .upToDate
        }
    }

    static func tone(phase: SyncCoordinator.Phase, failedRows: Int) -> Tone {
        if case .failed = phase { return .error }
        if failedRows > 0 { return .error }
        if case .waitingToRetry = phase { return .warning }
        return .normal
    }

    /// The Profile card only shows up when the user has something to know or do: offline, failed, or rows the server
    /// refused. A normal pass, a short pending moment and the restore (it has its own screen) stay out of sight.
    static func needsAttention(phase: SyncCoordinator.Phase, failedRows: Int) -> Bool {
        if failedRows > 0 { return true }
        switch phase {
        case .waitingToRetry, .failed: return true
        case .idle, .syncing, .restoring: return false
        }
    }

    /// "Sync now" is offered unless a pass is already running.
    static func canSyncNow(phase: SyncCoordinator.Phase) -> Bool {
        switch phase {
        case .syncing, .restoring: false
        case .idle, .waitingToRetry, .failed: true
        }
    }
}
