import Foundation

// Value types for routines and workouts (SwiftData models are not `Sendable`).

/// Targets of one exercise in a routine day. Limits equal the CHECK constraints of `public.routine_exercises`.
public struct RoutineExerciseInput: Sendable, Equatable {
    public var targetSets: Int
    public var targetRepsMin: Int?
    public var targetRepsMax: Int?
    public var targetRir: Int?
    public var supersetGroup: Int?
    public var restSeconds: Int?
    public var notes: String?

    public init(
        targetSets: Int = 3, targetRepsMin: Int? = nil, targetRepsMax: Int? = nil, targetRir: Int? = nil,
        supersetGroup: Int? = nil, restSeconds: Int? = nil, notes: String? = nil
    ) {
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRir = targetRir
        self.supersetGroup = supersetGroup
        self.restSeconds = restSeconds
        self.notes = notes
    }

    func validated() throws -> RoutineExerciseInput {
        guard (1...50).contains(targetSets) else { throw DataError.invalidValue("targetSets") }
        for (name, value) in [("targetRepsMin", targetRepsMin), ("targetRepsMax", targetRepsMax)] {
            if let value, !(0...100).contains(value) { throw DataError.invalidValue(name) }
        }
        if let low = targetRepsMin, let high = targetRepsMax, low > high { throw DataError.invalidValue("targetReps") }
        if let targetRir, !(0...10).contains(targetRir) { throw DataError.invalidValue("targetRir") }
        if let supersetGroup, supersetGroup < 1 { throw DataError.invalidValue("supersetGroup") }
        if let restSeconds, !(0...3600).contains(restSeconds) { throw DataError.invalidValue("restSeconds") }
        if let notes, notes.count > 2000 { throw DataError.invalidValue("notes") }
        return self
    }
}

/// One set. Limits equal the CHECK constraints of `public.sets`.
public struct SetInput: Sendable, Equatable {
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var rir: Int?
    public var setType: SetType
    public var isCompleted: Bool

    public init(
        weightKg: Double = 0, reps: Int = 0, rpe: Double? = nil, rir: Int? = nil, setType: SetType = .working,
        isCompleted: Bool = false
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.setType = setType
        self.isCompleted = isCompleted
    }

    /// Only a completed, non-warm-up set with at least one rep feeds Strength Scores and records.
    public var countsForScore: Bool { isCompleted && setType != .warmup && reps >= 1 }

    func validated() throws -> SetInput {
        guard weightKg.isFinite, (0...1000).contains(weightKg) else { throw DataError.invalidValue("weightKg") }
        guard (0...100).contains(reps) else { throw DataError.invalidValue("reps") }
        if let rpe, !(rpe.isFinite && (1...10).contains(rpe)) { throw DataError.invalidValue("rpe") }
        if let rir, !(0...10).contains(rir) { throw DataError.invalidValue("rir") }
        return self
    }
}

/// A whole workout in one value: used to start one (exercises optional) and to record finished history in one go.
public struct WorkoutDraft: Sendable, Equatable {
    public var name: String?
    public var startedAt: Date
    /// `nil` = the workout is active.
    public var endedAt: Date?
    public var routineId: UUID?
    public var routineDayId: UUID?
    public var notes: String?
    public var source: WorkoutSource
    public var exercises: [WorkoutExerciseDraft]

    public init(
        name: String? = nil, startedAt: Date, endedAt: Date? = nil, routineId: UUID? = nil,
        routineDayId: UUID? = nil, notes: String? = nil, source: WorkoutSource = .manual,
        exercises: [WorkoutExerciseDraft] = []
    ) {
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.routineId = routineId
        self.routineDayId = routineDayId
        self.notes = notes
        self.source = source
        self.exercises = exercises
    }
}

public struct WorkoutExerciseDraft: Sendable, Equatable {
    public var ref: ExerciseRef
    public var supersetGroup: Int?
    public var notes: String?
    public var sets: [SetInput]

    public init(ref: ExerciseRef, supersetGroup: Int? = nil, notes: String? = nil, sets: [SetInput] = []) {
        self.ref = ref
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.sets = sets
    }
}

// MARK: - Snapshots

public struct RoutineSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let name: String
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let syncState: SyncState
    /// Ordered by `position`.
    public let days: [RoutineDaySnapshot]

    public var exerciseCount: Int { days.reduce(0) { $0 + $1.exercises.count } }
    public var positionsAreContiguous: Bool {
        days.map(\.position).isContiguousFromZero && days.allSatisfy { $0.exercises.map(\.position).isContiguousFromZero }
    }
}

public struct RoutineDaySnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let routineId: UUID
    public let position: Int
    public let name: String
    public let exercises: [RoutineExerciseSnapshot]
}

public struct RoutineExerciseSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let routineDayId: UUID
    public let position: Int
    public let ref: ExerciseRef
    public let input: RoutineExerciseInput
}

public struct WorkoutSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let name: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let routineId: UUID?
    public let routineDayId: UUID?
    public let notes: String?
    public let source: WorkoutSource
    /// 1–5 "how did it feel" (P041).
    public let rating: Int?
    /// The Apple Health workout written for this one; nil until written.
    public let healthKitUUID: UUID?
    public let createdAt: Date
    public let updatedAt: Date
    public let syncState: SyncState
    /// Ordered by `position`.
    public let exercises: [WorkoutExerciseSnapshot]

    public var isActive: Bool { endedAt == nil }
    /// Same rule as `Workout.isSyncLocked`: an active workout is never overwritten by a sync pull.
    public var isSyncLocked: Bool { isActive }
    public var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    /// Sets that count towards scores: completed, not warm-up, at least one rep.
    public var scoringSets: [SetSnapshot] { exercises.flatMap(\.sets).filter(\.input.countsForScore) }
    public var positionsAreContiguous: Bool {
        exercises.map(\.position).isContiguousFromZero && exercises.allSatisfy { $0.sets.map(\.position).isContiguousFromZero }
    }
}

public struct WorkoutExerciseSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let workoutId: UUID
    public let position: Int
    public let ref: ExerciseRef
    public let supersetGroup: Int?
    public let notes: String?
    public let sets: [SetSnapshot]
}

public struct SetSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let workoutExerciseId: UUID
    public let position: Int
    public let input: SetInput
}

/// One past session of an exercise (for the exercise history and "last time" hints).
public struct ExerciseSession: Sendable, Equatable {
    public let workoutId: UUID
    public let date: Date
    /// Completed sets only, in order.
    public let sets: [SetSnapshot]
}

extension Array where Element == Int {
    /// `[]`, `[0]`, `[0, 1, 2]` …; the position invariant of every ordered child list.
    var isContiguousFromZero: Bool { sorted() == Array(0..<count) }
}
