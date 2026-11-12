import Foundation

/// Repository contracts. Every write sets `updatedAt` and `syncState = .pending` (docs/02-MIMARI.md §2.4).
/// Reads hide soft-deleted rows.

public protocol ProfileRepository: Sendable {
    func profile(userId: UUID) async throws -> ProfileSnapshot?
    /// Creates the user's profile or replaces its fields (also revives a soft-deleted one).
    @discardableResult
    func upsert(_ input: ProfileInput, userId: UUID) async throws -> ProfileSnapshot
    func delete(userId: UUID) async throws
}

public protocol MeasurementRepository: Sendable {
    @discardableResult
    func add(_ input: MeasurementInput, userId: UUID) async throws -> MeasurementSnapshot
    @discardableResult
    func update(id: UUID, with input: MeasurementInput) async throws -> MeasurementSnapshot
    func delete(id: UUID) async throws
    /// Newest day first.
    func all(userId: UUID) async throws -> [MeasurementSnapshot]
    func latest(userId: UUID) async throws -> MeasurementSnapshot?
}

public protocol ConsentRepository: Sendable {
    /// Appends a row; earlier rows are kept as the audit trail.
    @discardableResult
    func record(kind: ConsentKind, version: String, granted: Bool, userId: UUID) async throws -> ConsentSnapshot
    /// Latest row for the kind, i.e. the current state.
    func current(kind: ConsentKind, userId: UUID) async throws -> ConsentSnapshot?
    /// Oldest first.
    func history(userId: UUID) async throws -> [ConsentSnapshot]
}

public protocol SettingsRepository: Sendable {
    /// The user's settings; the row is created with the defaults on first read.
    @discardableResult
    func settings(userId: UUID) async throws -> SettingsSnapshot
    @discardableResult
    func update(_ input: SettingsInput, userId: UUID) async throws -> SettingsSnapshot
}

public protocol CustomExerciseRepository: Sendable {
    @discardableResult
    func create(_ input: CustomExerciseInput, userId: UUID) async throws -> CustomExerciseSnapshot
    @discardableResult
    func update(id: UUID, with input: CustomExerciseInput) async throws -> CustomExerciseSnapshot
    /// Soft delete.
    func delete(id: UUID) async throws
    func exercise(id: UUID) async throws -> CustomExerciseSnapshot?
    /// The user's exercises, A–Z by name.
    func all(userId: UUID) async throws -> [CustomExerciseSnapshot]
}

public protocol RoutineRepository: Sendable {
    @discardableResult
    func create(name: String, notes: String?, userId: UUID) async throws -> RoutineSnapshot
    @discardableResult
    func update(id: UUID, name: String, notes: String?) async throws -> RoutineSnapshot
    /// Soft delete; the days and exercises are marked deleted with it.
    func delete(id: UUID) async throws
    func routine(id: UUID) async throws -> RoutineSnapshot?
    /// The user's routines, A–Z by name, each with its days and exercises.
    func all(userId: UUID) async throws -> [RoutineSnapshot]

    @discardableResult
    func addDay(routineId: UUID, name: String) async throws -> RoutineDaySnapshot
    func renameDay(id: UUID, to name: String) async throws
    func moveDay(id: UUID, to position: Int) async throws
    func deleteDay(id: UUID) async throws

    @discardableResult
    func addExercise(dayId: UUID, ref: ExerciseRef, input: RoutineExerciseInput) async throws -> RoutineExerciseSnapshot
    func updateExercise(id: UUID, with input: RoutineExerciseInput) async throws
    func moveExercise(id: UUID, to position: Int) async throws
    func deleteExercise(id: UUID) async throws

    /// Copies a routine (days and exercises, new ids) under `name`.
    @discardableResult
    func duplicate(routineId: UUID, name: String) async throws -> RoutineSnapshot
    /// Copies a day right behind the original under `name`.
    @discardableResult
    func duplicateDay(id: UUID, name: String) async throws -> RoutineDaySnapshot
    /// Copies an exercise right behind the original (without its superset group).
    @discardableResult
    func duplicateExercise(id: UUID) async throws -> RoutineExerciseSnapshot
    /// Groups two or more exercises of one day into a superset: they are moved next to each other.
    func setSuperset(exerciseIds: [UUID]) async throws
    /// Takes one exercise out of its superset; a group left with a single member dissolves.
    func clearSuperset(exerciseId: UUID) async throws
    /// Puts a routine back to `snapshot` (same ids): the undo of an edit.
    func restore(_ snapshot: RoutineSnapshot) async throws
}

public protocol WorkoutRepository: Sendable {
    /// Creates a workout. With `endedAt == nil` it becomes the active one; throws `activeWorkoutExists` if the user
    /// already has one. A draft with `endedAt` records finished history.
    @discardableResult
    func start(_ draft: WorkoutDraft, userId: UUID) async throws -> WorkoutSnapshot
    func activeWorkout(userId: UUID) async throws -> WorkoutSnapshot?
    func workout(id: UUID) async throws -> WorkoutSnapshot?
    @discardableResult
    func finish(id: UUID, at date: Date) async throws -> WorkoutSnapshot
    func updateDetails(id: UUID, name: String?, notes: String?) async throws
    /// 1…5, or `nil` to clear.
    func setRating(id: UUID, rating: Int?) async throws
    /// Remembers (or, with `nil`, forgets) the Apple Health workout written for this one.
    func setHealthKitUUID(id: UUID, uuid: UUID?) async throws
    /// Puts a soft-deleted workout back with the exercises and sets that were deleted together with it (the undo of
    /// `delete`). Does nothing when the workout is not deleted.
    func restore(id: UUID) async throws
    /// Finished workouts (not deleted, not active) that started before `before` (`nil` = from the newest), newest first.
    func finishedWorkouts(userId: UUID, before: Date?, limit: Int) async throws -> [WorkoutSnapshot]
    /// Every finished workout's start date, for the calendar (newest first).
    func finishedDates(userId: UUID) async throws -> [Date]
    /// Soft delete with the exercises and sets.
    func delete(id: UUID) async throws

    @discardableResult
    func addExercise(workoutId: UUID, ref: ExerciseRef, supersetGroup: Int?) async throws -> WorkoutExerciseSnapshot
    func moveExercise(id: UUID, to position: Int) async throws
    func removeExercise(id: UUID) async throws
    /// Sets the note of one exercise in a workout (`nil` clears it).
    func updateExerciseNotes(id: UUID, notes: String?) async throws

    @discardableResult
    func addSet(workoutExerciseId: UUID, input: SetInput) async throws -> SetSnapshot
    func updateSet(id: UUID, with input: SetInput) async throws
    func removeSet(id: UUID) async throws

    /// Workouts whose `startedAt` lies in `[from, to)`, newest first.
    func workouts(userId: UUID, from: Date, to: Date) async throws -> [WorkoutSnapshot]
    /// Finished sessions of an exercise that have at least one completed set, newest first.
    func history(userId: UUID, ref: ExerciseRef, limit: Int) async throws -> [ExerciseSession]
    /// Completed sets of the exercise's most recent finished session (empty when never done).
    func lastSets(userId: UUID, ref: ExerciseRef) async throws -> [SetSnapshot]
    /// Distinct exercises of the most recent finished workouts, newest first.
    func recentExercises(userId: UUID, limit: Int) async throws -> [ExerciseRef]
    /// Stores the sets reported during onboarding as one finished workout (source = onboarding), replacing an earlier
    /// one. A `nil` or empty draft only removes the earlier workout.
    func replaceOnboardingWorkout(_ draft: WorkoutDraft?, userId: UUID) async throws
}

/// Ordered child rows share this so reordering is written once.
protocol Positioned: SyncableRecord {
    var position: Int { get set }
}

extension SchemaV4.RoutineDay: Positioned {}
extension SchemaV4.RoutineExercise: Positioned {}
extension SchemaV4.WorkoutExercise: Positioned {}
extension SchemaV4.SetEntry: Positioned {}

enum Ordering {
    /// Renumbers `items` 0…n-1 in their current order; only changed rows are marked pending.
    static func compact<T: Positioned>(_ items: [T], at now: Date) {
        for (index, item) in items.sorted(by: { $0.position < $1.position }).enumerated() where item.position != index {
            item.position = index
            item.markPending(at: now)
        }
    }

    /// Moves the item with `id` to `target` (clamped) and renumbers the rest without gaps.
    static func move<T: Positioned>(_ items: [T], id: UUID, to target: Int, at now: Date) throws {
        var ordered = items.sorted { $0.position < $1.position }
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { throw DataError.notFound }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: min(max(target, 0), ordered.count))
        for (index, entry) in ordered.enumerated() where entry.position != index {
            entry.position = index
            entry.markPending(at: now)
        }
    }
}
