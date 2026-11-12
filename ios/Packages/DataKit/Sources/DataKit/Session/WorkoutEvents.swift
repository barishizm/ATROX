import Foundation

/// What the active workout engine reports to the UI, the rest timer (P037), Live Activity (P038) and scoring.
public enum WorkoutEvent: Sendable, Equatable {
    case setCompleted(workoutExerciseId: UUID, setId: UUID)
    /// Every set of the exercise is completed (sent once, by the set that completes it).
    case exerciseCompleted(workoutExerciseId: UUID)
    case prAchieved(PersonalRecordHit)
    case workoutFinished(WorkoutSnapshot)
}

/// A personal best reached by a just-completed set.
public struct PersonalRecordHit: Sendable, Equatable {
    public let ref: ExerciseRef
    public let kind: RecordKind
    public let value: Double
    public let setId: UUID
    /// The standing value this one beat.
    public let previousValue: Double?
    /// The e1RM jumped more than 12% over the previous best: ask "Did you enter this set correctly?" before celebrating.
    public let needsConfirmation: Bool

    public init(
        ref: ExerciseRef, kind: RecordKind, value: Double, setId: UUID, previousValue: Double? = nil,
        needsConfirmation: Bool = false
    ) {
        self.ref = ref
        self.kind = kind
        self.value = value
        self.setId = setId
        self.previousValue = previousValue
        self.needsConfirmation = needsConfirmation
    }
}

/// Decides whether a completed set is a personal record (rules: `StrengthKit.RecordMath`) and keeps the stored
/// records consistent when history changes.
public protocol PersonalRecordDetecting: Sendable {
    /// Records the just-completed set breaks, best first. The very first set of an exercise breaks none.
    func records(for set: SetSnapshot, ref: ExerciseRef, userId: UUID, workoutId: UUID) async throws -> [PersonalRecordHit]
    /// A set of the exercise was edited, un-completed or deleted, or a workout containing it was deleted: rebuild
    /// the exercise's records from its history.
    func exerciseChanged(ref: ExerciseRef, userId: UUID) async throws
}

extension PersonalRecordDetecting {
    public func exerciseChanged(ref: ExerciseRef, userId: UUID) async throws {}
}

public enum WorkoutSessionError: Error, Equatable, Sendable {
    /// The operation needs an active workout (none started, or it was finished/cancelled).
    case notActive
    /// A workout is already running in this session.
    case alreadyActive
    case unknownExercise
    case unknownSet
    case unknownRoutineDay
}
