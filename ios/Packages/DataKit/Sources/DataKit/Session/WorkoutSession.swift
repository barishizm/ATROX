import Foundation
import Observation

/// The active workout engine (P035): a UI-free state machine over `WorkoutRepository`.
///
/// - Every operation is written to SwiftData before it returns; `workout` is then re-read from the store, so the
///   in-memory state never drifts from what survives an app kill. `restore()` brings the active workout back.
/// - Elapsed time is `now - startedAt` from the injected clock; nothing ticks in the background.
/// - The active workout is sync-locked (`WorkoutSnapshot.isSyncLocked`) until it is finished or cancelled.
@MainActor
@Observable
public final class WorkoutSession {
    public enum Phase: Equatable, Sendable {
        /// No workout yet (call `restore`, `startEmpty` or `start(routineId:dayId:)`).
        case idle
        case active
        case finished(WorkoutSnapshot)
        /// Finished without a single completed set: nothing was kept.
        case discarded
        case cancelled
    }

    public enum FinishResult: Equatable, Sendable {
        case finished(WorkoutSnapshot)
        case discarded
    }

    public let userId: UUID
    public private(set) var phase: Phase = .idle
    /// The active workout as stored; `nil` unless `phase == .active`.
    public private(set) var workout: WorkoutSnapshot?
    /// "Last time" values per workout exercise id: the completed sets of the exercise's previous finished session.
    public private(set) var previous: [UUID: [SetInput]] = [:]

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let routines: (any RoutineRepository)?
    @ObservationIgnored private let records: (any PersonalRecordDetecting)?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<WorkoutEvent>.Continuation] = [:]

    public init(
        userId: UUID, workouts: any WorkoutRepository, routines: (any RoutineRepository)? = nil,
        records: (any PersonalRecordDetecting)? = nil, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.userId = userId
        self.workouts = workouts
        self.routines = routines
        self.records = records
        self.clock = clock
    }

    // MARK: Events

    /// A new stream of events; each subscriber gets every event sent after it subscribed.
    public func events() -> AsyncStream<WorkoutEvent> {
        let (stream, continuation) = AsyncStream<WorkoutEvent>.makeStream()
        let key = UUID()
        subscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[key] = nil }
        }
        return stream
    }

    private func send(_ event: WorkoutEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    // MARK: Time

    /// Time since the start, from the clock (`date` defaults to now). Zero when no workout is active.
    public func elapsed(at date: Date? = nil) -> TimeInterval {
        guard let workout, phase == .active else { return 0 }
        return max(0, (date ?? clock()).timeIntervalSince(workout.startedAt))
    }

    // MARK: Start and recovery

    /// Picks up the user's active workout from the store (after an app kill). Returns whether one was found.
    @discardableResult
    public func restore() async throws -> Bool {
        guard let active = try await workouts.activeWorkout(userId: userId) else { return false }
        workout = active
        phase = .active
        previous = [:]
        for exercise in active.exercises {
            previous[exercise.id] = try await lastTime(exercise.ref)
        }
        return true
    }

    /// Starts an empty workout.
    public func startEmpty(name: String? = nil) async throws {
        try ensureCanStart()
        let started = try await workouts.start(
            WorkoutDraft(name: name, startedAt: clock(), source: .manual), userId: userId
        )
        workout = started
        previous = [:]
        phase = .active
    }

    /// Starts a workout from a routine day: one exercise per routine row, sets pre-filled from the row's targets and
    /// last time's values (`WorkoutPrefill`).
    public func start(routineId: UUID, dayId: UUID) async throws {
        try ensureCanStart()
        guard let routine = try await routines?.routine(id: routineId),
              let day = routine.days.first(where: { $0.id == dayId })
        else { throw WorkoutSessionError.unknownRoutineDay }
        var drafts: [WorkoutExerciseDraft] = []
        var lastTimes: [[SetInput]] = []
        for row in day.exercises {
            let last = try await lastTime(row.ref)
            lastTimes.append(last)
            drafts.append(
                WorkoutExerciseDraft(
                    ref: row.ref, supersetGroup: row.input.supersetGroup,
                    sets: WorkoutPrefill.sets(target: row.input, last: last)
                )
            )
        }
        let started = try await workouts.start(
            WorkoutDraft(
                name: day.name, startedAt: clock(), routineId: routineId, routineDayId: dayId, source: .routine,
                exercises: drafts
            ),
            userId: userId
        )
        workout = started
        previous = Dictionary(uniqueKeysWithValues: zip(started.exercises.map(\.id), lastTimes))
        phase = .active
    }

    private func ensureCanStart() throws {
        if phase == .active { throw WorkoutSessionError.alreadyActive }
    }

    // MARK: Sets

    public func completeSet(_ setId: UUID) async throws {
        let (exercise, set) = try locate(setId)
        guard !set.input.isCompleted else { return }
        var input = set.input
        input.isCompleted = true
        try await workouts.updateSet(id: setId, with: input)
        try await reload()
        send(.setCompleted(workoutExerciseId: exercise.id, setId: setId))
        if let updated = self.exercise(exercise.id), !updated.sets.isEmpty, updated.sets.allSatisfy(\.input.isCompleted) {
            send(.exerciseCompleted(workoutExerciseId: exercise.id))
        }
        if let records, let workout, let stored = self.set(setId) {
            for hit in try await records.records(for: stored, ref: exercise.ref, userId: userId, workoutId: workout.id) {
                send(.prAchieved(hit))
            }
        }
    }

    /// Undo of `completeSet`.
    public func uncompleteSet(_ setId: UUID) async throws {
        try await editSet(setId) { $0.isCompleted = false }
    }

    public func setWeight(_ setId: UUID, kg: Double) async throws {
        try await editSet(setId) { $0.weightKg = kg }
    }

    public func setReps(_ setId: UUID, reps: Int) async throws {
        try await editSet(setId) { $0.reps = reps }
    }

    public func setRir(_ setId: UUID, rir: Int?) async throws {
        try await editSet(setId) { $0.rir = rir }
    }

    public func setType(_ setId: UUID, to type: SetType) async throws {
        try await editSet(setId) { $0.setType = type }
    }

    /// Any change to one set's values (validated by the repository; invalid values throw and change nothing).
    public func editSet(_ setId: UUID, _ change: (inout SetInput) -> Void) async throws {
        let (_, set) = try locate(setId)
        var input = set.input
        change(&input)
        guard input != set.input else { return }
        try await workouts.updateSet(id: setId, with: input)
        try await reload()
    }

    /// Appends a set copied from the exercise's last one (not completed).
    @discardableResult
    public func addSet(to workoutExerciseId: UUID) async throws -> UUID {
        guard let exercise = exercise(workoutExerciseId) else { throw activeOr(.unknownExercise) }
        let added = try await workouts.addSet(
            workoutExerciseId: workoutExerciseId, input: WorkoutPrefill.nextSet(after: exercise.sets.map(\.input))
        )
        try await reload()
        return added.id
    }

    /// Removes a set; removing the last one leaves the exercise in place with no sets.
    public func removeSet(_ setId: UUID) async throws {
        _ = try locate(setId)
        try await workouts.removeSet(id: setId)
        try await reload()
    }

    // MARK: Exercises

    /// Appends an exercise with sets pre-filled from last time.
    @discardableResult
    public func addExercise(_ ref: ExerciseRef) async throws -> UUID {
        guard let workout, phase == .active else { throw WorkoutSessionError.notActive }
        return try await insertExercise(ref, into: workout.id)
    }

    public func removeExercise(_ workoutExerciseId: UUID) async throws {
        guard exercise(workoutExerciseId) != nil else { throw activeOr(.unknownExercise) }
        try await workouts.removeExercise(id: workoutExerciseId)
        previous[workoutExerciseId] = nil
        try await reload()
    }

    /// Swaps an exercise for another at the same position; its sets are replaced by the new exercise's pre-fill.
    @discardableResult
    public func replaceExercise(_ workoutExerciseId: UUID, with ref: ExerciseRef) async throws -> UUID {
        guard let workout, let old = exercise(workoutExerciseId) else { throw activeOr(.unknownExercise) }
        let newId = try await insertExercise(ref, into: workout.id, supersetGroup: old.supersetGroup)
        try await workouts.updateExerciseNotes(id: newId, notes: old.notes)
        try await workouts.removeExercise(id: workoutExerciseId)
        try await workouts.moveExercise(id: newId, to: old.position)
        previous[workoutExerciseId] = nil
        try await reload()
        return newId
    }

    public func moveExercise(_ workoutExerciseId: UUID, to position: Int) async throws {
        guard exercise(workoutExerciseId) != nil else { throw activeOr(.unknownExercise) }
        try await workouts.moveExercise(id: workoutExerciseId, to: position)
        try await reload()
    }

    public func setExerciseNotes(_ workoutExerciseId: UUID, notes: String?) async throws {
        guard exercise(workoutExerciseId) != nil else { throw activeOr(.unknownExercise) }
        try await workouts.updateExerciseNotes(id: workoutExerciseId, notes: Self.clean(notes))
        try await reload()
    }

    public func setNotes(_ notes: String?) async throws {
        guard let workout, phase == .active else { throw WorkoutSessionError.notActive }
        try await workouts.updateDetails(id: workout.id, name: workout.name, notes: Self.clean(notes))
        try await reload()
    }

    // MARK: End

    /// Ends the workout. With `dropIncomplete` (default) sets that were never completed are removed first, and so are
    /// exercises left without sets. A workout without any completed set is discarded (soft-deleted) instead.
    @discardableResult
    public func finish(dropIncomplete: Bool = true) async throws -> FinishResult {
        guard let workout, phase == .active else { throw WorkoutSessionError.notActive }
        let completed = workout.exercises.flatMap(\.sets).filter(\.input.isCompleted)
        guard !completed.isEmpty else {
            try await workouts.delete(id: workout.id)
            end(.discarded)
            return .discarded
        }
        if dropIncomplete {
            for exercise in workout.exercises {
                let open = exercise.sets.filter { !$0.input.isCompleted }
                if open.count == exercise.sets.count {
                    try await workouts.removeExercise(id: exercise.id)
                } else {
                    for entry in open { try await workouts.removeSet(id: entry.id) }
                }
            }
        }
        let finished = try await workouts.finish(id: workout.id, at: max(clock(), workout.startedAt))
        end(.finished(finished))
        send(.workoutFinished(finished))
        return .finished(finished)
    }

    /// Throws the workout away (soft delete with its exercises and sets).
    public func cancel() async throws {
        guard let workout, phase == .active else { throw WorkoutSessionError.notActive }
        try await workouts.delete(id: workout.id)
        end(.cancelled)
    }

    private func end(_ phase: Phase) {
        self.phase = phase
        workout = nil
        previous = [:]
    }

    // MARK: Helpers

    private func insertExercise(_ ref: ExerciseRef, into workoutId: UUID, supersetGroup: Int? = nil) async throws -> UUID {
        let last = try await lastTime(ref)
        let row = try await workouts.addExercise(workoutId: workoutId, ref: ref, supersetGroup: supersetGroup)
        for input in WorkoutPrefill.sets(target: nil, last: last) {
            try await workouts.addSet(workoutExerciseId: row.id, input: input)
        }
        previous[row.id] = last
        try await reload()
        return row.id
    }

    private func lastTime(_ ref: ExerciseRef) async throws -> [SetInput] {
        try await workouts.lastSets(userId: userId, ref: ref).map(\.input)
    }

    private func reload() async throws {
        guard let id = workout?.id else { return }
        workout = try await workouts.workout(id: id)
    }

    public func exercise(_ id: UUID) -> WorkoutExerciseSnapshot? {
        guard phase == .active else { return nil }
        return workout?.exercises.first { $0.id == id }
    }

    public func set(_ id: UUID) -> SetSnapshot? {
        guard phase == .active else { return nil }
        return workout?.exercises.lazy.flatMap(\.sets).first { $0.id == id }
    }

    private func locate(_ setId: UUID) throws -> (WorkoutExerciseSnapshot, SetSnapshot) {
        guard phase == .active, let workout else { throw WorkoutSessionError.notActive }
        for exercise in workout.exercises {
            if let set = exercise.sets.first(where: { $0.id == setId }) { return (exercise, set) }
        }
        throw WorkoutSessionError.unknownSet
    }

    private func activeOr(_ error: WorkoutSessionError) -> WorkoutSessionError {
        phase == .active ? error : .notActive
    }

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
