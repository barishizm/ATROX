import Foundation
import SwiftData

/// Diary logs: adds `DiaryLog` (water, activities, steps, notes, fasts and the goal weight). Every other model is
/// shared with V8, so V8 → V9 is a lightweight migration (one new entity).
public enum SchemaV9: VersionedSchema {
    public static let versionIdentifier = Schema.Version(9, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV8.models + [DiaryLog.self]
    }
}

public typealias DiaryLog = SchemaV9.DiaryLog

extension SchemaV9 {
    /// One small diary fact of a day; `kind` says which. Mirrors `public.diary_logs`.
    @Model
    public final class DiaryLog: SyncableRecord {
        #Index<DiaryLog>([\.userId, \.kindRaw, \.at], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var kindRaw: String
        public var at: Date
        public var endedAt: Date?
        public var amount: Double
        public var quantity: Double
        public var label: String
        public var text: String

        public init(id: UUID = UUID(), userId: UUID, input: DiaryLogInput, now: Date = Date()) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            kindRaw = input.kind.rawValue
            at = input.at
            endedAt = input.endedAt
            amount = input.amount
            quantity = input.quantity
            label = input.label
            text = input.text
        }

        func apply(_ input: DiaryLogInput) {
            kindRaw = input.kind.rawValue
            at = input.at
            endedAt = input.endedAt
            amount = input.amount
            quantity = input.quantity
            label = input.label
            text = input.text
        }

        public var input: DiaryLogInput {
            DiaryLogInput(
                kind: DiaryLogKind(rawValue: kindRaw) ?? .note, at: at, endedAt: endedAt, amount: amount, quantity: quantity,
                label: label, text: text
            )
        }

        public var snapshot: DiaryLogSnapshot {
            DiaryLogSnapshot(id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, syncState: syncState, input: input)
        }
    }
}
