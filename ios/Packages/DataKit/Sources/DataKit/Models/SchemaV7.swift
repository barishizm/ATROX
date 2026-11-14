import CryptoKit
import Foundation
import SwiftData

/// P069: adds `InsightRecord` (the insight list, what was shown and what was dismissed). Every other model is shared
/// with V6, so V6 → V7 is a lightweight migration (one new entity).
public enum SchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV6.models + [InsightRecord.self]
    }
}

public typealias InsightRecord = SchemaV7.InsightRecord

extension SchemaV7 {
    /// One insight per (kind, subject). Mirrors `public.insights`. The id is derived from that pair, so two devices that
    /// detect the same thing write the same row. The coach's `get_insights` tool reads the active rows.
    @Model
    public final class InsightRecord: SyncableRecord {
        #Index<InsightRecord>([\.userId, \.kindRaw, \.subject], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var kindRaw: String
        public var subject: String
        public var severityRaw: String
        public var priority: Double
        public var actionRaw: String
        /// `InsightPayload` as JSON (names and numbers, no text).
        public var payload: String
        /// The condition holds as of the last check.
        public var isActive: Bool
        public var detectedAt: Date
        public var lastShownAt: Date?
        public var dismissedAt: Date?

        public init(
            userId: UUID, kind: InsightKind, subject: String, severity: InsightSeverity, priority: Double, action: InsightAction,
            payload: InsightPayload, detectedAt: Date, now: Date = Date()
        ) {
            id = Self.id(userId: userId, kind: kind.rawValue, subject: subject)
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            kindRaw = kind.rawValue
            self.subject = subject
            severityRaw = severity.rawValue
            self.priority = priority
            actionRaw = action.rawValue
            self.payload = payload.json
            isActive = true
            self.detectedAt = detectedAt
            lastShownAt = nil
            dismissedAt = nil
        }

        /// Deterministic id of (user, kind, subject): first 16 bytes of its SHA-256, as a v8 UUID.
        public static func id(userId: UUID, kind: String, subject: String) -> UUID {
            var bytes = Array(SHA256.hash(data: Data([userId.uuidString, "insight", kind, subject].joined(separator: "|").utf8)).prefix(16))
            bytes[6] = (bytes[6] & 0x0F) | 0x80
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }

        /// The value form the app works with; nil for a row with an unknown kind (written by a newer app).
        public var insight: Insight? {
            guard let kind = InsightKind(rawValue: kindRaw) else { return nil }
            return Insight(
                id: id, kind: kind, subject: subject, severity: InsightSeverity(rawValue: severityRaw) ?? .mild, priority: priority,
                action: InsightAction(rawValue: actionRaw) ?? .askCoach, payload: InsightPayload(json: payload), isActive: isActive,
                detectedAt: detectedAt, lastShownAt: lastShownAt, dismissedAt: dismissedAt
            )
        }
    }
}
