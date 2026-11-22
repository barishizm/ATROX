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

    /// Logs one finished set for an exercise on a given day without an active workout (the "Add Set" of the exercise
    /// screen). It joins a finished workout of that day that already has the exercise; otherwise it records a new,
    /// already finished workout holding just this set. Never creates or touches an active workout.
    @discardableResult
    public func logSet(ref: ExerciseRef, input: SetInput, on date: Date, calendar: Calendar = .current) async throws -> UUID {
        var set = input
        set.isCompleted = true
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let sameDay = try await workouts.workouts(userId: userId, from: start, to: end)
            .first { $0.endedAt != nil && $0.exercises.contains { $0.ref == ref } }
        let workoutId: UUID
        if let sameDay, let row = sameDay.exercises.first(where: { $0.ref == ref }) {
            try await workouts.addSet(workoutExerciseId: row.id, input: set)
            workoutId = sameDay.id
        } else {
            let draft = WorkoutDraft(
                startedAt: date, endedAt: date, source: .manual, exercises: [WorkoutExerciseDraft(ref: ref, sets: [set])]
            )
            workoutId = try await workouts.start(draft, userId: userId).id
        }
        try await recordsChanged(ref)
        return workoutId
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

extension SetInput {
    /// A finished working set as the "Add Set" sheet logs it. `rir` may be a half step (0.5 … 4.5, the last stop
    /// meaning "4+"): the whole-number part goes to `rir`, rounded down so the 1RM estimate stays conservative, and
    /// a half step is also kept as `rpe` (10 − RiR) so it can be shown back unchanged.
    public static func logged(weightKg: Double, reps: Int, rir: Double?, tag: SetTag? = nil) -> SetInput {
        var input = SetInput(weightKg: weightKg, reps: reps, setType: .working, isCompleted: true, tag: tag)
        if let rir {
            let clamped = min(max(rir, 0), 9)
            input.rir = Int(clamped.rounded(.down))
            if clamped.rounded(.down) != clamped { input.rpe = 10 - clamped }
        }
        return input
    }
}
