import Foundation

/// Fields shared by every locally stored, synced model (docs/02-MIMARI.md §2.3).
/// Weights are always kg and lengths cm; unit conversion happens only in the UI.
public protocol SyncableRecord: AnyObject {
    /// Client-generated primary key, identical to the server row id.
    var id: UUID { get }
    var userId: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    /// Soft delete marker; rows are never removed locally until the server confirms the tombstone.
    var deletedAt: Date? { get set }
    var syncStateRaw: String { get set }
}

public extension SyncableRecord {
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .pending }
        set { syncStateRaw = newValue.rawValue }
    }

    var isSoftDeleted: Bool { deletedAt != nil }

    /// Every local write goes through this so the sync engine picks the row up.
    func markPending(at date: Date) {
        updatedAt = date
        syncState = .pending
    }

    func markDeleted(at date: Date) {
        deletedAt = date
        markPending(at: date)
    }
}
