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

    public init(ref: ExerciseRef, kind: RecordKind, value: Double, setId: UUID) {
        self.ref = ref
        self.kind = kind
        self.value = value
        self.setId = setId
    }
}

/// Decides whether a completed set is a personal record. The real rules arrive in P040; until then the session
/// runs without one and never sends `prAchieved`.
public protocol PersonalRecordDetecting: Sendable {
    func records(for set: SetSnapshot, ref: ExerciseRef, userId: UUID, workoutId: UUID) async throws -> [PersonalRecordHit]
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
