import CryptoKit
import Foundation
import SwiftData

/// P064: adds `ScoreSnapshot` (score history for charts). Every other model is shared with V5, so V5 → V6 is a
/// lightweight migration (one new entity).
public enum SchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV5.models + [ScoreSnapshot.self]
    }
}

public typealias ScoreSnapshot = SchemaV6.ScoreSnapshot

public enum SnapshotScope: String, Sendable, Codable, CaseIterable {
    case exercise, muscle, overall
}

extension SchemaV6 {
    /// A point of a score time series. Mirrors `public.score_snapshots`. The id is derived from the natural key
    /// (`ScoreSnapshot.id(...)`), so two devices computing the same day write the same row.
    @Model
    public final class ScoreSnapshot: SyncableRecord {
        #Index<ScoreSnapshot>([\.userId, \.scopeRaw, \.key, \.referenceGroupRaw, \.date], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var scopeRaw: String
        public var key: String
        public var referenceGroupRaw: String
        public var score: Double
        public var z: Double
        public var confidenceRaw: String
        public var modelVersion: String
        public var date: Date

        public var scope: SnapshotScope {
            get { SnapshotScope(rawValue: scopeRaw) ?? .exercise }
            set { scopeRaw = newValue.rawValue }
        }

        public init(
            userId: UUID, scope: SnapshotScope, key: String, referenceGroup: String, score: Double, z: Double,
            confidence: String, modelVersion: String, date: Date, now: Date = Date()
        ) {
            id = Self.id(userId: userId, scope: scope.rawValue, key: key, referenceGroup: referenceGroup, date: date)
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            scopeRaw = scope.rawValue
            self.key = key
            referenceGroupRaw = referenceGroup
            self.score = score
            self.z = z
            confidenceRaw = confidence
            self.modelVersion = modelVersion
            self.date = date
        }

        /// Deterministic id of (user, scope, key, group, calendar day): first 16 bytes of its SHA-256, as a v8 UUID.
        public static func id(userId: UUID, scope: String, key: String, referenceGroup: String, date: Date) -> UUID {
            let text = [userId.uuidString, scope, key, referenceGroup, SyncTime.day(date)].joined(separator: "|")
            var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
            bytes[6] = (bytes[6] & 0x0F) | 0x80
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }
    }
}
