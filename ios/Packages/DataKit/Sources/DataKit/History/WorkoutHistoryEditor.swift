import Foundation

/// Edits and deletes *finished* workouts (P042) and keeps everything derived from them true: personal records are
/// rebuilt for each touched exercise (`PersonalRecordDetecting.exerciseChanged`) and the Apple Health workout is
/// removed with a deleted workout and written again when the delete is undone.
///
/// Summaries are never stored (`WorkoutSummary`, month totals and charts are computed from the sets), so they are
/// current by construction; only records need the rebuild.
public struct WorkoutHistoryEditor: Sendable {
    public let userId: UUID
    private let workouts: any WorkoutRepository
    private let records: (any PersonalRecordDetecting)?
    private let health: WorkoutHealthRecorder?

    public init(
        userId: UUID, workouts: any WorkoutRepository, records: (any PersonalRecordDetecting)? = nil,
        health: WorkoutHealthRecorder? = nil
    ) {
        self.userId = userId
        self.workouts = workouts
        self.records = records
        self.health = health
    }

    // MARK: Sets

    /// Changes one set (weight, reps, RIR, type, completion).
    public func editSet(workoutId: UUID, setId: UUID, _ change: @Sendable (inout SetInput) -> Void) async throws {
        let (exercise, set) = try await locate(setId, in: workoutId)
        var input = set.input
        change(&input)
        guard input != set.input else { return }
        try await workouts.updateSet(id: setId, with: input)
        try await recordsChanged(exercise.ref)
    }

    /// Adds a completed set copied from the exercise's last one.
    @discardableResult
    public func addSet(workoutId: UUID, exerciseId: UUID) async throws -> SetSnapshot {
        let workout = try await existing(workoutId)
        guard let exercise = workout.exercises.first(where: { $0.id == exerciseId }) else { throw DataError.notFound }
        var input = WorkoutPrefill.nextSet(after: exercise.sets.map(\.input))
        input.isCompleted = true
        let added = try await workouts.addSet(workoutExerciseId: exerciseId, input: input)
        try await recordsChanged(exercise.ref)
        return added
    }

    public func removeSet(workoutId: UUID, setId: UUID) async throws {
        let (exercise, _) = try await locate(setId, in: workoutId)
        try await workouts.removeSet(id: setId)
        try await recordsChanged(exercise.ref)
    }

    // MARK: Exercises

    /// Adds an exercise with last time's sets, marked as done.
    @discardableResult
    public func addExercise(workoutId: UUID, ref: ExerciseRef) async throws -> WorkoutExerciseSnapshot {
        _ = try await existing(workoutId)
        let last = try await workouts.lastSets(userId: userId, ref: ref).map(\.input)
        let row = try await workouts.addExercise(workoutId: workoutId, ref: ref, supersetGroup: nil)
        for var input in WorkoutPrefill.sets(target: nil, last: last) {
            input.isCompleted = true
            try await workouts.addSet(workoutExerciseId: row.id, input: input)
        }
        try await recordsChanged(ref)
        return try await existing(workoutId).exercises.first { $0.id == row.id } ?? row
    }

    public func removeExercise(workoutId: UUID, exerciseId: UUID) async throws {
        let workout = try await existing(workoutId)
        guard let exercise = workout.exercises.first(where: { $0.id == exerciseId }) else { throw DataError.notFound }
        try await workouts.removeExercise(id: exerciseId)
        try await recordsChanged(exercise.ref)
    }

    // MARK: Workout

    public func updateDetails(workoutId: UUID, name: String?, notes: String?) async throws {
        try await workouts.updateDetails(id: workoutId, name: Self.clean(name), notes: Self.clean(notes))
    }

    public func setRating(workoutId: UUID, rating: Int?) async throws {
        try await workouts.setRating(id: workoutId, rating: rating)
    }

    /// Soft-deletes the workout; the returned snapshot is what `undoDelete` brings back.
    @discardableResult
    public func delete(workoutId: UUID) async throws -> WorkoutSnapshot {
        let workout = try await existing(workoutId)
        await health?.remove(workoutId: workoutId)
        try await workouts.delete(id: workoutId)
        for ref in Self.scoredRefs(of: workout) { try await recordsChanged(ref) }
        return workout
    }

    /// Undo of `delete`: the workout returns with its exercises and sets, records are rebuilt, Health is written again.
    public func undoDelete(workoutId: UUID) async throws {
        try await workouts.restore(id: workoutId)
        let workout = try await existing(workoutId)
        for ref in Self.scoredRefs(of: workout) { try await recordsChanged(ref) }
        await health?.record(workoutId: workoutId)
    }

    // MARK: Helpers

    private func existing(_ id: UUID) async throws -> WorkoutSnapshot {
        guard let workout = try await workouts.workout(id: id) else { throw DataError.notFound }
        return workout
    }

    private func locate(_ setId: UUID, in workoutId: UUID) async throws -> (WorkoutExerciseSnapshot, SetSnapshot) {
        let workout = try await existing(workoutId)
        for exercise in workout.exercises {
            if let set = exercise.sets.first(where: { $0.id == setId }) { return (exercise, set) }
        }
        throw DataError.notFound
    }

    private func recordsChanged(_ ref: ExerciseRef) async throws {
        try await records?.exerciseChanged(ref: ref, userId: userId)
    }

    private static func scoredRefs(of workout: WorkoutSnapshot) -> Set<ExerciseRef> {
        Set(workout.exercises.filter { $0.sets.contains(where: \.input.countsForScore) }.map(\.ref))
    }

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
