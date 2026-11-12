import Foundation
import SwiftData

extension SchemaV4 {
    /// A training program. Mirrors `public.routines`. Children point at their parent by id (like the server's
    /// composite foreign keys), so the sync engine can push each table on its own.
    @Model
    public final class Routine: SyncableRecord {
        #Index<Routine>([\.userId, \.deletedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var name: String
        public var notes: String?

        public init(id: UUID = UUID(), userId: UUID, name: String, notes: String? = nil, now: Date = Date()) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.name = name
            self.notes = notes
        }
    }

    /// One day of a routine ("Push", "Pull", "Legs"). Mirrors `public.routine_days`.
    @Model
    public final class RoutineDay: SyncableRecord {
        #Index<RoutineDay>([\.routineId, \.position], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var routineId: UUID
        /// 0-based and gap-free among the live days of the routine.
        public var position: Int
        public var name: String

        public init(id: UUID = UUID(), userId: UUID, routineId: UUID, position: Int, name: String, now: Date = Date()) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.routineId = routineId
            self.position = position
            self.name = name
        }
    }

    /// An exercise in a routine day with its targets. Mirrors `public.routine_exercises`.
    @Model
    public final class RoutineExercise: SyncableRecord {
        #Index<RoutineExercise>([\.routineDayId, \.position], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var routineDayId: UUID
        /// 0-based and gap-free among the live exercises of the day.
        public var position: Int
        public var exerciseId: String?
        public var customExerciseId: UUID?

        public var targetSets: Int
        public var targetRepsMin: Int?
        public var targetRepsMax: Int?
        public var targetRir: Int?
        /// Exercises sharing a number (≥ 1) within a day form one superset.
        public var supersetGroup: Int?
        public var restSeconds: Int?
        public var notes: String?

        public var ref: ExerciseRef? { ExerciseRef(exerciseId: exerciseId, customExerciseId: customExerciseId) }

        public init(
            id: UUID = UUID(), userId: UUID, routineDayId: UUID, position: Int, ref: ExerciseRef,
            input: RoutineExerciseInput = RoutineExerciseInput(), now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.routineDayId = routineDayId
            self.position = position
            exerciseId = ref.catalogId
            customExerciseId = ref.customId
            targetSets = input.targetSets
            targetRepsMin = input.targetRepsMin
            targetRepsMax = input.targetRepsMax
            targetRir = input.targetRir
            supersetGroup = input.supersetGroup
            restSeconds = input.restSeconds
            notes = input.notes
        }

        func apply(_ input: RoutineExerciseInput) {
            targetSets = input.targetSets
            targetRepsMin = input.targetRepsMin
            targetRepsMax = input.targetRepsMax
            targetRir = input.targetRir
            supersetGroup = input.supersetGroup
            restSeconds = input.restSeconds
            notes = input.notes
        }
    }
}
