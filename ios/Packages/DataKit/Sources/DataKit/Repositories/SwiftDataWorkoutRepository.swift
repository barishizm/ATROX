import Foundation
import SwiftData

@ModelActor
public actor SwiftDataWorkoutRepository: WorkoutRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    // MARK: Workouts

    @discardableResult
    public func start(_ draft: WorkoutDraft, userId: UUID) throws -> WorkoutSnapshot {
        let model = try insert(draft, userId: userId)
        try modelContext.save()
        return try snapshot(of: model)
    }

    public func activeWorkout(userId: UUID) throws -> WorkoutSnapshot? {
        try activeModel(userId: userId).map(snapshot(of:))
    }

    public func workout(id: UUID) throws -> WorkoutSnapshot? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(snapshot(of:))
    }

    @discardableResult
    public func finish(id: UUID, at date: Date) throws -> WorkoutSnapshot {
        let model = try live(Workout.self, id: id)
        guard model.endedAt == nil else { throw DataError.alreadyFinished }
        guard date >= model.startedAt else { throw DataError.invalidValue("endedAt") }
        model.endedAt = date
        model.markPending(at: clock())
        try modelContext.save()
        return try snapshot(of: model)
    }

    public func updateDetails(id: UUID, name: String?, notes: String?) throws {
        let model = try live(Workout.self, id: id)
        guard (name?.count ?? 0) <= 200, (notes?.count ?? 0) <= 4000 else { throw DataError.invalidValue("details") }
        model.name = name
        model.notes = notes
        model.markPending(at: clock())
        try modelContext.save()
    }

    public func delete(id: UUID) throws {
        let model = try live(Workout.self, id: id)
        softDelete(model, at: clock())
        try modelContext.save()
    }

    public func setRating(id: UUID, rating: Int?) throws {
        let model = try live(Workout.self, id: id)
        if let rating, !(1...5).contains(rating) { throw DataError.invalidValue("rating") }
        model.rating = rating
        model.markPending(at: clock())
        try modelContext.save()
    }

    public func setHealthKitUUID(id: UUID, uuid: UUID?) throws {
        let model = try live(Workout.self, id: id)
        model.healthKitUUID = uuid
        model.markPending(at: clock())
        try modelContext.save()
    }

    public func restore(id: UUID) throws {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first, let deletedAt = model.deletedAt else { return }
        let now = clock()
        // Only rows deleted *with* the workout come back; a set removed earlier stays removed.
        let rows = try modelContext.fetch(
            FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.workoutId == id && $0.deletedAt == deletedAt })
        )
        let rowIds = rows.map(\.id)
        let sets = rowIds.isEmpty ? [] : try modelContext.fetch(
            FetchDescriptor<SetEntry>(
                predicate: #Predicate { rowIds.contains($0.workoutExerciseId) && $0.deletedAt == deletedAt }
            )
        )
        for set in sets { set.deletedAt = nil; set.markPending(at: now) }
        for row in rows { row.deletedAt = nil; row.markPending(at: now) }
        model.deletedAt = nil
        model.markPending(at: now)
        try modelContext.save()
    }

    public func finishedWorkouts(userId: UUID, before: Date?, limit: Int) throws -> [WorkoutSnapshot] {
        guard limit > 0 else { return [] }
        let cutoff = before ?? .distantFuture
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.userId == userId && $0.deletedAt == nil && $0.endedAt != nil && $0.startedAt < cutoff
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(snapshot(of:))
    }

    public func finishedDates(userId: UUID) throws -> [Date] {
        try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        ).map(\.startedAt)
    }

    // MARK: Exercises and sets

    @discardableResult
    public func addExercise(workoutId: UUID, ref: ExerciseRef, supersetGroup: Int?) throws -> WorkoutExerciseSnapshot {
        let workout = try live(Workout.self, id: workoutId)
        if let supersetGroup, supersetGroup < 1 { throw DataError.invalidValue("supersetGroup") }
        let model = WorkoutExercise(
            userId: workout.userId, workoutId: workoutId, position: try exercises(of: workoutId).count, ref: ref,
            supersetGroup: supersetGroup, now: clock()
        )
        modelContext.insert(model)
        try modelContext.save()
        return try exerciseSnapshot(model)
    }

    public func moveExercise(id: UUID, to position: Int) throws {
        let model = try live(WorkoutExercise.self, id: id)
        try Ordering.move(try exercises(of: model.workoutId), id: id, to: position, at: clock())
        try modelContext.save()
    }

    public func removeExercise(id: UUID) throws {
        let model = try live(WorkoutExercise.self, id: id)
        let now = clock()
        for set in try sets(of: [id]) { set.markDeleted(at: now) }
        model.markDeleted(at: now)
        Ordering.compact(try exercises(of: model.workoutId).filter { $0.id != id }, at: now)
        try modelContext.save()
    }

    public func updateExerciseNotes(id: UUID, notes: String?) throws {
        let model = try live(WorkoutExercise.self, id: id)
        guard (notes?.count ?? 0) <= 2000 else { throw DataError.invalidValue("notes") }
        model.notes = notes
        model.markPending(at: clock())
        try modelContext.save()
    }

    @discardableResult
    public func addSet(workoutExerciseId: UUID, input: SetInput) throws -> SetSnapshot {
        let exercise = try live(WorkoutExercise.self, id: workoutExerciseId)
        let model = SetEntry(
            userId: exercise.userId, workoutExerciseId: workoutExerciseId,
            position: try sets(of: [workoutExerciseId]).count, input: try input.validated(), now: clock()
        )
        modelContext.insert(model)
        try modelContext.save()
        return Self.snapshot(of: model)
    }

    public func updateSet(id: UUID, with input: SetInput) throws {
        let model = try live(SetEntry.self, id: id)
        model.apply(try input.validated())
        model.markPending(at: clock())
        try modelContext.save()
    }

    public func removeSet(id: UUID) throws {
        let model = try live(SetEntry.self, id: id)
        let now = clock()
        model.markDeleted(at: now)
        Ordering.compact(try sets(of: [model.workoutExerciseId]).filter { $0.id != id }, at: now)
        try modelContext.save()
    }

    // MARK: Queries

    public func workouts(userId: UUID, from: Date, to: Date) throws -> [WorkoutSnapshot] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.userId == userId && $0.deletedAt == nil && $0.startedAt >= from && $0.startedAt < to
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(snapshot(of:))
    }

    public func history(userId: UUID, ref: ExerciseRef, limit: Int) throws -> [ExerciseSession] {
        guard limit > 0 else { return [] }
        let rows = try exerciseRows(userId: userId, ref: ref)
        let workoutIds = Set(rows.map(\.workoutId))
        guard !workoutIds.isEmpty else { return [] }
        let finished = try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate {
                    workoutIds.contains($0.id) && $0.deletedAt == nil && $0.endedAt != nil
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        )
        var sessions: [ExerciseSession] = []
        for workout in finished {
            let ids = rows.filter { $0.workoutId == workout.id }.map(\.id)
            let done = try sets(of: ids).filter(\.isCompleted).sorted { $0.position < $1.position }.map(Self.snapshot(of:))
            if !done.isEmpty { sessions.append(ExerciseSession(workoutId: workout.id, date: workout.startedAt, sets: done)) }
            if sessions.count == limit { break }
        }
        return sessions
    }

    public func lastSets(userId: UUID, ref: ExerciseRef) throws -> [SetSnapshot] {
        try history(userId: userId, ref: ref, limit: 1).first?.sets ?? []
    }

    public func recentExercises(userId: UUID, limit: Int) throws -> [ExerciseRef] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        var seen = Set<ExerciseRef>()
        var result: [ExerciseRef] = []
        for workout in try modelContext.fetch(descriptor) {
            for exercise in try exercises(of: workout.id) {
                guard let ref = exercise.ref, seen.insert(ref).inserted else { continue }
                result.append(ref)
                if result.count == limit { return result }
            }
        }
        return result
    }

    public func replaceOnboardingWorkout(_ draft: WorkoutDraft?, userId: UUID) throws {
        let onboarding = WorkoutSource.onboarding.rawValue
        let earlier = try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.sourceRaw == onboarding }
            )
        )
        let now = clock()
        for workout in earlier { softDelete(workout, at: now) }
        if var draft, !draft.exercises.isEmpty {
            draft.source = .onboarding
            if draft.endedAt == nil { draft.endedAt = draft.startedAt }
            _ = try insert(draft, userId: userId)
        }
        try modelContext.save()
    }

    // MARK: Helpers

    private func insert(_ draft: WorkoutDraft, userId: UUID) throws -> Workout {
        if let ended = draft.endedAt, ended < draft.startedAt { throw DataError.invalidValue("endedAt") }
        if draft.endedAt == nil, try activeModel(userId: userId) != nil { throw DataError.activeWorkoutExists }
        // Validate everything before inserting anything, so a bad set never leaves a half-written workout.
        let validSets = try draft.exercises.map { exercise in
            if let group = exercise.supersetGroup, group < 1 { throw DataError.invalidValue("supersetGroup") }
            return try exercise.sets.map { try $0.validated() }
        }
        let now = clock()
        let workout = Workout(
            userId: userId, name: draft.name, startedAt: draft.startedAt, endedAt: draft.endedAt,
            routineId: draft.routineId, routineDayId: draft.routineDayId, notes: draft.notes, source: draft.source,
            now: now
        )
        modelContext.insert(workout)
        for (position, exercise) in draft.exercises.enumerated() {
            let row = WorkoutExercise(
                userId: userId, workoutId: workout.id, position: position, ref: exercise.ref,
                supersetGroup: exercise.supersetGroup, notes: exercise.notes, now: now
            )
            modelContext.insert(row)
            for (index, input) in validSets[position].enumerated() {
                modelContext.insert(
                    SetEntry(userId: userId, workoutExerciseId: row.id, position: index, input: input, now: now)
                )
            }
        }
        return workout
    }

    private func activeModel(userId: UUID) throws -> Workout? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.endedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func live<T: PersistentModel & SyncableRecord>(_ type: T.Type, id: UUID) throws -> T {
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first, !model.isSoftDeleted else { throw DataError.notFound }
        return model
    }

    private func exercises(of workoutId: UUID) throws -> [WorkoutExercise] {
        try modelContext.fetch(
            FetchDescriptor<WorkoutExercise>(
                predicate: #Predicate { $0.workoutId == workoutId && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.position)]
            )
        )
    }

    /// Live exercise rows of the user that point at `ref`, across all workouts.
    private func exerciseRows(userId: UUID, ref: ExerciseRef) throws -> [WorkoutExercise] {
        switch ref {
        case .catalog(let id):
            let target: String? = id
            return try modelContext.fetch(
                FetchDescriptor<WorkoutExercise>(
                    predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.exerciseId == target }
                )
            )
        case .custom(let id):
            let target: UUID? = id
            return try modelContext.fetch(
                FetchDescriptor<WorkoutExercise>(
                    predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil && $0.customExerciseId == target }
                )
            )
        }
    }

    private func sets(of exerciseIds: [UUID]) throws -> [SetEntry] {
        guard !exerciseIds.isEmpty else { return [] }
        return try modelContext.fetch(
            FetchDescriptor<SetEntry>(
                predicate: #Predicate { exerciseIds.contains($0.workoutExerciseId) && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.position)]
            )
        )
    }

    private func softDelete(_ workout: Workout, at now: Date) {
        let rows = (try? exercises(of: workout.id)) ?? []
        for set in (try? sets(of: rows.map(\.id))) ?? [] { set.markDeleted(at: now) }
        for row in rows { row.markDeleted(at: now) }
        workout.markDeleted(at: now)
    }

    private func snapshot(of workout: Workout) throws -> WorkoutSnapshot {
        WorkoutSnapshot(
            id: workout.id, userId: workout.userId, name: workout.name, startedAt: workout.startedAt,
            endedAt: workout.endedAt, routineId: workout.routineId, routineDayId: workout.routineDayId,
            notes: workout.notes, source: workout.source, rating: workout.rating,
            healthKitUUID: workout.healthKitUUID, createdAt: workout.createdAt, updatedAt: workout.updatedAt,
            syncState: workout.syncState, exercises: try exercises(of: workout.id).map(exerciseSnapshot)
        )
    }

    private func exerciseSnapshot(_ row: WorkoutExercise) throws -> WorkoutExerciseSnapshot {
        WorkoutExerciseSnapshot(
            id: row.id, workoutId: row.workoutId, position: row.position,
            ref: row.ref ?? .catalog(row.exerciseId ?? ""), supersetGroup: row.supersetGroup, notes: row.notes,
            sets: try sets(of: [row.id]).map(Self.snapshot(of:))
        )
    }

    private static func snapshot(of set: SetEntry) -> SetSnapshot {
        SetSnapshot(
            id: set.id, workoutExerciseId: set.workoutExerciseId, position: set.position,
            input: SetInput(
                weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, rir: set.rir, setType: set.setType,
                isCompleted: set.isCompleted
            )
        )
    }
}
