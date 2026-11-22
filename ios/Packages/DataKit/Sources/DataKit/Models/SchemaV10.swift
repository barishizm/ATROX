import Foundation
import SwiftData

/// Set tags: `SetEntry` gains the optional `tagRaw` (V9 → V10 is a lightweight migration). The V4 `SetEntry` class stays
/// frozen in `Workouts.swift`; every other model is shared with V9.
public enum SchemaV10: VersionedSchema {
    public static let versionIdentifier = Schema.Version(10, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV9.models.filter { ObjectIdentifier($0) != ObjectIdentifier(SchemaV4.SetEntry.self) } + [SetEntry.self]
    }
}

extension SchemaV10 {
    /// One set (V10: adds `tagRaw`). Mirrors `public.sets`. Only completed, non-warm-up sets count towards scores and records.
    @Model
    public final class SetEntry: SyncableRecord {
        #Index<SetEntry>([\.workoutExerciseId, \.position], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var workoutExerciseId: UUID
        /// 0-based and gap-free among the live sets of the exercise.
        public var position: Int
        public var weightKg: Double
        public var reps: Int
        public var rpe: Double?
        public var rir: Int?
        public var setTypeRaw: String
        public var isCompleted: Bool
        /// Optional colour tag the lifter put on the set ("Add tag"); nil = none.
        public var tagRaw: String?

        public var tag: SetTag? {
            get { tagRaw.flatMap(SetTag.init(rawValue:)) }
            set { tagRaw = newValue?.rawValue }
        }

        public var setType: SetType {
            get { SetType(rawValue: setTypeRaw) ?? .working }
            set { setTypeRaw = newValue.rawValue }
        }

        public init(
            id: UUID = UUID(), userId: UUID, workoutExerciseId: UUID, position: Int, input: SetInput = SetInput(),
            now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.workoutExerciseId = workoutExerciseId
            self.position = position
            weightKg = input.weightKg
            reps = input.reps
            rpe = input.rpe
            rir = input.rir
            setTypeRaw = input.setType.rawValue
            isCompleted = input.isCompleted
            tagRaw = input.tag?.rawValue
        }

        func apply(_ input: SetInput) {
            weightKg = input.weightKg
            reps = input.reps
            rpe = input.rpe
            rir = input.rir
            setType = input.setType
            isCompleted = input.isCompleted
            tagRaw = input.tag?.rawValue
        }
    }
}
