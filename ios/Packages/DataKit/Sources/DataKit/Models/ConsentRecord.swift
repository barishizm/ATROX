import Foundation
import SwiftData

extension SchemaV1 {
    /// Append-only consent log; the current state of a kind is its latest row. Mirrors `public.consents`.
    /// Rows are never edited or deleted, so `deletedAt` stays nil and `updatedAt == createdAt`.
    @Model
    public final class ConsentRecord: SyncableRecord {
        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var kindRaw: String
        public var version: String
        public var granted: Bool

        public var kind: ConsentKind {
            get { ConsentKind(rawValue: kindRaw) ?? .terms }
            set { kindRaw = newValue.rawValue }
        }

        public init(
            id: UUID = UUID(), userId: UUID, kind: ConsentKind, version: String, granted: Bool, now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            self.createdAt = now
            self.updatedAt = now
            self.deletedAt = nil
            self.syncStateRaw = SyncState.pending.rawValue
            self.kindRaw = kind.rawValue
            self.version = version
            self.granted = granted
        }
    }
}
