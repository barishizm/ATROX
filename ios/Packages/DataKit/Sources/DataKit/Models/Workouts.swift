import Foundation
import SwiftData

extension SchemaV4 {
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
        }
    }

    /// An exercise performed in a workout. Mirrors `public.workout_exercises`.
    @Model
    public final class WorkoutExercise: SyncableRecord {
        #Index<WorkoutExercise>([\.workoutId, \.position], [\.userId, \.exerciseId], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var workoutId: UUID
        /// 0-based and gap-free among the live exercises of the workout.
        public var position: Int
        public var exerciseId: String?
        public var customExerciseId: UUID?
        public var supersetGroup: Int?
        public var notes: String?

        public var ref: ExerciseRef? { ExerciseRef(exerciseId: exerciseId, customExerciseId: customExerciseId) }

        public init(
            id: UUID = UUID(), userId: UUID, workoutId: UUID, position: Int, ref: ExerciseRef,
            supersetGroup: Int? = nil, notes: String? = nil, now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            self.workoutId = workoutId
            self.position = position
            exerciseId = ref.catalogId
            customExerciseId = ref.customId
            self.supersetGroup = supersetGroup
            self.notes = notes
        }
    }

    /// One set. Mirrors `public.sets`. Only completed, non-warm-up sets count towards scores and records.
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
        }

        func apply(_ input: SetInput) {
            weightKg = input.weightKg
            reps = input.reps
            rpe = input.rpe
            rir = input.rir
            setType = input.setType
            isCompleted = input.isCompleted
        }
    }

    /// A personal best. Mirrors `public.personal_records`. Computing them is a later step; the table is ready.
    @Model
    public final class PersonalRecord: SyncableRecord {
        #Index<PersonalRecord>([\.userId, \.exerciseId, \.kindRaw], [\.userId, \.updatedAt])

        @Attribute(.unique) public var id: UUID
        public var userId: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var deletedAt: Date?
        public var syncStateRaw: String

        public var exerciseId: String?
        public var customExerciseId: UUID?
        public var kindRaw: String
        public var value: Double
        public var setId: UUID?
        public var date: Date

        public var kind: RecordKind {
            get { RecordKind(rawValue: kindRaw) ?? .weight }
            set { kindRaw = newValue.rawValue }
        }

        public var ref: ExerciseRef? { ExerciseRef(exerciseId: exerciseId, customExerciseId: customExerciseId) }

        public init(
            id: UUID = UUID(), userId: UUID, ref: ExerciseRef, kind: RecordKind, value: Double, setId: UUID? = nil,
            date: Date, now: Date = Date()
        ) {
            self.id = id
            self.userId = userId
            createdAt = now
            updatedAt = now
            deletedAt = nil
            syncStateRaw = SyncState.pending.rawValue
            exerciseId = ref.catalogId
            customExerciseId = ref.customId
            kindRaw = kind.rawValue
            self.value = value
            self.setId = setId
            self.date = date
        }
    }
}
