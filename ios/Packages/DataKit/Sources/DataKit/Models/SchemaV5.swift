import Foundation
import SwiftData

/// P041: `Workout` gains `rating` and `healthKitUUID` (both optional, so V4 → V5 is a lightweight migration). The
/// V4 `Workout` class stays frozen in `Workouts.swift`; every other model is shared with V4.
public enum SchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV4.models.filter { ObjectIdentifier($0) != ObjectIdentifier(SchemaV4.Workout.self) } + [Workout.self]
    }
}

public typealias Workout = SchemaV5.Workout

extension SchemaV5 {
    /// One training session. Mirrors `public.workouts`; `sourceRaw` is local-only until the server column exists.
    /// A workout is *active* while `endedAt == nil` (and it is not soft-deleted); a user has at most one.
    @Model
    public final class Workout: SyncableRecord {
        #Index<Workout>([\.userId, \.startedAt], [\.userId, \.endedAt], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        /// Kept as history even if the routine is later deleted.
        public var routineId: UUID?
        public var routineDayId: UUID?
        public var name: String?
        public var startedAt: Date
        public var endedAt: Date?
        public var notes: String?
        public var sourceRaw: String
        /// 1–5 "how did it feel", optional (P041).
        public var rating: Int?
        /// The Apple Health workout written for this one (P041); stops a second write and lets a delete remove it.
        public var healthKitUUID: UUID?

        public var source: WorkoutSource {
            get { WorkoutSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        public var isActive: Bool { endedAt == nil && deletedAt == nil }

        /// The active workout is locked for sync (docs/02-MIMARI.md §2.3): a pull never overwrites it until it ends.
        /// The sync engine (P044) must skip pulled rows of a locked workout and of its exercises and sets.
        public var isSyncLocked: Bool { isActive }

        public init(
            id: UUID = UUID(), userId: UUID, name: String? = nil, startedAt: Date, endedAt: Date? = nil,
            routineId: UUID? = nil, routineDayId: UUID? = nil, notes: String? = nil, source: WorkoutSource = .manual,
            now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.routineId = routineId
            self.routineDayId = routineDayId
            self.name = name
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.notes = notes
            sourceRaw = source.rawValue
            rating = nil
            healthKitUUID = nil
        }
    }
}
