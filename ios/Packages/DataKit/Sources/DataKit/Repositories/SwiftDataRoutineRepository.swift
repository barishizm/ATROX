import Foundation
import SwiftData

@ModelActor
public actor SwiftDataRoutineRepository: RoutineRepository {
    private var clock: @Sendable () -> Date = { Date() }

    public init(modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
    }

    // MARK: Routines

    @discardableResult
    public func create(name: String, notes: String?, userId: UUID) throws -> RoutineSnapshot {
        let model = Routine(userId: userId, name: try Self.validName(name), notes: notes, now: clock())
        modelContext.insert(model)
        try modelContext.save()
        return try snapshot(of: model)
    }

    @discardableResult
    public func update(id: UUID, name: String, notes: String?) throws -> RoutineSnapshot {
        let model = try live(Routine.self, id: id)
        model.name = try Self.validName(name)
        model.notes = notes
        model.markPending(at: clock())
        try modelContext.save()
        return try snapshot(of: model)
    }

    public func delete(id: UUID) throws {
        let model = try live(Routine.self, id: id)
        let now = clock()
        for day in try days(of: id) { try softDelete(day: day, at: now) }
        model.markDeleted(at: now)
        try modelContext.save()
    }

    public func routine(id: UUID) throws -> RoutineSnapshot? {
        var descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(snapshot(of:))
    }

    public func all(userId: UUID) throws -> [RoutineSnapshot] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map(snapshot(of:))
    }

    // MARK: Days

    @discardableResult
    public func addDay(routineId: UUID, name: String) throws -> RoutineDaySnapshot {
        let routine = try live(Routine.self, id: routineId)
        let existing = try days(of: routineId)
        let day = RoutineDay(
            userId: routine.userId, routineId: routineId, position: existing.count, name: try Self.validName(name),
            now: clock()
        )
        modelContext.insert(day)
        try modelContext.save()
        return try daySnapshot(day)
    }

    public func renameDay(id: UUID, to name: String) throws {
        let day = try live(RoutineDay.self, id: id)
        day.name = try Self.validName(name)
        day.markPending(at: clock())
        try modelContext.save()
    }

    public func moveDay(id: UUID, to position: Int) throws {
        let day = try live(RoutineDay.self, id: id)
        try Ordering.move(try days(of: day.routineId), id: id, to: position, at: clock())
        try modelContext.save()
    }

    public func deleteDay(id: UUID) throws {
        let day = try live(RoutineDay.self, id: id)
        let now = clock()
        try softDelete(day: day, at: now)
        Ordering.compact(try days(of: day.routineId), at: now)
        try modelContext.save()
    }

    // MARK: Exercises

    @discardableResult
    public func addExercise(dayId: UUID, ref: ExerciseRef, input: RoutineExerciseInput) throws -> RoutineExerciseSnapshot {
        let day = try live(RoutineDay.self, id: dayId)
        let model = RoutineExercise(
            userId: day.userId, routineDayId: dayId, position: try exercises(of: dayId).count, ref: ref,
            input: try input.validated(), now: clock()
        )
        modelContext.insert(model)
        try modelContext.save()
        return Self.snapshot(of: model)
    }

    public func updateExercise(id: UUID, with input: RoutineExerciseInput) throws {
        let model = try live(RoutineExercise.self, id: id)
        model.apply(try input.validated())
        model.markPending(at: clock())
        try modelContext.save()
    }

    public func moveExercise(id: UUID, to position: Int) throws {
        let model = try live(RoutineExercise.self, id: id)
        try Ordering.move(try exercises(of: model.routineDayId), id: id, to: position, at: clock())
        try modelContext.save()
    }

    public func deleteExercise(id: UUID) throws {
        let model = try live(RoutineExercise.self, id: id)
        let now = clock()
        model.markDeleted(at: now)
        Ordering.compact(try exercises(of: model.routineDayId).filter { $0.id != id }, at: now)
        try modelContext.save()
    }

    // MARK: Helpers

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(trimmed.count) else { throw DataError.invalidValue("name") }
        return trimmed
    }

    private func live<T: PersistentModel & SyncableRecord>(_ type: T.Type, id: UUID) throws -> T {
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let model = try modelContext.fetch(descriptor).first, !model.isSoftDeleted else { throw DataError.notFound }
        return model
    }

    private func days(of routineId: UUID) throws -> [RoutineDay] {
        let descriptor = FetchDescriptor<RoutineDay>(
            predicate: #Predicate { $0.routineId == routineId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func exercises(of dayId: UUID) throws -> [RoutineExercise] {
        let descriptor = FetchDescriptor<RoutineExercise>(
            predicate: #Predicate { $0.routineDayId == dayId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func softDelete(day: RoutineDay, at now: Date) throws {
        for exercise in try exercises(of: day.id) { exercise.markDeleted(at: now) }
        day.markDeleted(at: now)
    }

    private func snapshot(of routine: Routine) throws -> RoutineSnapshot {
        RoutineSnapshot(
            id: routine.id, userId: routine.userId, name: routine.name, notes: routine.notes,
            createdAt: routine.createdAt, updatedAt: routine.updatedAt, syncState: routine.syncState,
            days: try days(of: routine.id).map(daySnapshot)
        )
    }

    private func daySnapshot(_ day: RoutineDay) throws -> RoutineDaySnapshot {
        RoutineDaySnapshot(
            id: day.id, routineId: day.routineId, position: day.position, name: day.name,
            exercises: try exercises(of: day.id).map(Self.snapshot(of:))
        )
    }

    private static func snapshot(of model: RoutineExercise) -> RoutineExerciseSnapshot {
        RoutineExerciseSnapshot(
            id: model.id, routineDayId: model.routineDayId, position: model.position,
            // The store only ever holds rows written through `ExerciseRef`.
            ref: model.ref ?? .catalog(model.exerciseId ?? ""),
            input: RoutineExerciseInput(
                targetSets: model.targetSets, targetRepsMin: model.targetRepsMin, targetRepsMax: model.targetRepsMax,
                targetRir: model.targetRir, supersetGroup: model.supersetGroup, restSeconds: model.restSeconds,
                notes: model.notes
            )
        )
    }
}
