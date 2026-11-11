import Foundation

/// Sync status shared by every local model (docs/02-MIMARI.md §2.3).
/// Placeholder public type; SwiftData models arrive in later steps.
public enum SyncState: String, Sendable, Codable, CaseIterable {
    case synced
    case pending
    case failed
}
