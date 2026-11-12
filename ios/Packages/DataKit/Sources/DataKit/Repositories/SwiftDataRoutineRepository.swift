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
        try normalizeSupersets(dayId: model.routineDayId)
        try modelContext.save()
    }

    public func moveExercise(id: UUID, to position: Int) throws {
        let model = try live(RoutineExercise.self, id: id)
        try Ordering.move(try exercises(of: model.routineDayId), id: id, to: position, at: clock())
        try normalizeSupersets(dayId: model.routineDayId)
        try modelContext.save()
    }

    public func deleteExercise(id: UUID) throws {
        let model = try live(RoutineExercise.self, id: id)
        let now = clock()
        model.markDeleted(at: now)
        Ordering.compact(try exercises(of: model.routineDayId).filter { $0.id != id }, at: now)
        try normalizeSupersets(dayId: model.routineDayId)
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

extension SwiftDataRoutineRepository {
    // MARK: Copies

    @discardableResult
    public func duplicate(routineId: UUID, name: String) throws -> RoutineSnapshot {
        let source = try live(Routine.self, id: routineId)
        let now = clock()
        let copy = Routine(userId: source.userId, name: try Self.validName(name), notes: source.notes, now: now)
        modelContext.insert(copy)
        for day in try days(of: routineId) {
            let newDay = RoutineDay(
                userId: source.userId, routineId: copy.id, position: day.position, name: day.name, now: now
            )
            modelContext.insert(newDay)
            for exercise in try exercises(of: day.id) { modelContext.insert(clone(exercise, into: newDay.id, now: now)) }
        }
        try modelContext.save()
        return try snapshot(of: copy)
    }

    @discardableResult
    public func duplicateDay(id: UUID, name: String) throws -> RoutineDaySnapshot {
        let source = try live(RoutineDay.self, id: id)
        let now = clock()
        let copy = RoutineDay(
            userId: source.userId, routineId: source.routineId, position: try days(of: source.routineId).count,
            name: try Self.validName(name), now: now
        )
        modelContext.insert(copy)
        for exercise in try exercises(of: id) { modelContext.insert(clone(exercise, into: copy.id, now: now)) }
        try modelContext.save()
        try Ordering.move(try days(of: source.routineId), id: copy.id, to: source.position + 1, at: now)
        try modelContext.save()
        return try daySnapshot(copy)
    }

    @discardableResult
    public func duplicateExercise(id: UUID) throws -> RoutineExerciseSnapshot {
        let source = try live(RoutineExercise.self, id: id)
        let now = clock()
        let copy = clone(source, into: source.routineDayId, now: now)
        copy.position = try exercises(of: source.routineDayId).count
        copy.supersetGroup = nil
        modelContext.insert(copy)
        try modelContext.save()
        try Ordering.move(try exercises(of: source.routineDayId), id: copy.id, to: source.position + 1, at: now)
        try normalizeSupersets(dayId: source.routineDayId)
        try modelContext.save()
        return Self.snapshot(of: copy)
    }

    // MARK: Supersets

    public func setSuperset(exerciseIds: [UUID]) throws {
        let unique = Array(Set(exerciseIds))
        guard unique.count >= 2 else { throw DataError.invalidValue("supersetGroup") }
        let chosen = try unique.map { try live(RoutineExercise.self, id: $0) }
        guard let dayId = chosen.first?.routineDayId, chosen.allSatisfy({ $0.routineDayId == dayId }) else {
            throw DataError.invalidValue("supersetGroup")
        }
        let now = clock()
        let day = try exercises(of: dayId)
        let group = (day.compactMap(\.supersetGroup).max() ?? 0) + 1
        let members = day.filter { unique.contains($0.id) }
        // The members take the place of the first one, in their current relative order.
        var ordered = day.filter { !unique.contains($0.id) }
        let firstIndex = day.firstIndex { $0.id == members[0].id } ?? 0
        let insertAt = day[..<firstIndex].filter { !unique.contains($0.id) }.count
        ordered.insert(contentsOf: members, at: insertAt)
        for (index, exercise) in ordered.enumerated() {
            let isMember = unique.contains(exercise.id)
            if exercise.position != index || (isMember && exercise.supersetGroup != group) {
                exercise.position = index
                if isMember { exercise.supersetGroup = group }
                exercise.markPending(at: now)
            }
        }
        try normalizeSupersets(dayId: dayId)
        try modelContext.save()
    }

    public func clearSuperset(exerciseId: UUID) throws {
        let model = try live(RoutineExercise.self, id: exerciseId)
        guard model.supersetGroup != nil else { return }
        model.supersetGroup = nil
        model.markPending(at: clock())
        try normalizeSupersets(dayId: model.routineDayId)
        try modelContext.save()
    }

    /// Superset groups must be runs of two or more neighbours. Each contiguous run keeps a group (the first one the
    /// old number, later ones fresh numbers); lone members lose the group.
    private func normalizeSupersets(dayId: UUID) throws {
        let day = try exercises(of: dayId)
        let now = clock()
        var nextFresh = (day.compactMap(\.supersetGroup).max() ?? 0) + 1
        var target: [UUID: Int?] = [:]
        var index = 0
        var seen: Set<Int> = []
        while index < day.count {
            guard let group = day[index].supersetGroup else { index += 1; continue }
            var end = index
            while end + 1 < day.count, day[end + 1].supersetGroup == group { end += 1 }
            var number: Int?
            if end > index {
                if seen.insert(group).inserted {
                    number = group
                } else {
                    number = nextFresh
                    nextFresh += 1
                }
            }
            for position in index...end { target[day[position].id] = .some(number) }
            index = end + 1
        }
        for exercise in day {
            guard let wanted = target[exercise.id] else { continue }
            if exercise.supersetGroup != wanted {
                exercise.supersetGroup = wanted
                exercise.markPending(at: now)
            }
        }
    }

    // MARK: Undo

    public func restore(_ snapshot: RoutineSnapshot) throws {
        let now = clock()
        let routineId = snapshot.id
        var routineFetch = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == routineId })
        routineFetch.fetchLimit = 1
        guard let routine = try modelContext.fetch(routineFetch).first else { throw DataError.notFound }
        routine.name = snapshot.name
        routine.notes = snapshot.notes
        routine.deletedAt = nil
        routine.markPending(at: now)

        let allDays = try modelContext.fetch(FetchDescriptor<RoutineDay>(predicate: #Predicate { $0.routineId == routineId }))
        var dayById = Dictionary(uniqueKeysWithValues: allDays.map { ($0.id, $0) })
        let keptDays = Set(snapshot.days.map(\.id))
        for day in allDays where !keptDays.contains(day.id) && !day.isSoftDeleted { try softDelete(day: day, at: now) }
        for daySnapshot in snapshot.days {
            let day: RoutineDay
            if let existing = dayById[daySnapshot.id] {
                day = existing
            } else {
                day = RoutineDay(
                    id: daySnapshot.id, userId: routine.userId, routineId: routineId, position: daySnapshot.position,
                    name: daySnapshot.name, now: now
                )
                modelContext.insert(day)
                dayById[day.id] = day
            }
            day.name = daySnapshot.name
            day.position = daySnapshot.position
            day.deletedAt = nil
            day.markPending(at: now)

            let dayId = day.id
            let allExercises = try modelContext.fetch(
                FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineDayId == dayId })
            )
            let byId = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })
            let keptExercises = Set(daySnapshot.exercises.map(\.id))
            for exercise in allExercises where !keptExercises.contains(exercise.id) && !exercise.isSoftDeleted {
                exercise.markDeleted(at: now)
            }
            for exerciseSnapshot in daySnapshot.exercises {
                if let exercise = byId[exerciseSnapshot.id] {
                    exercise.position = exerciseSnapshot.position
                    exercise.exerciseId = exerciseSnapshot.ref.catalogId
                    exercise.customExerciseId = exerciseSnapshot.ref.customId
                    exercise.apply(exerciseSnapshot.input)
                    exercise.deletedAt = nil
                    exercise.markPending(at: now)
                } else {
                    modelContext.insert(RoutineExercise(
                        id: exerciseSnapshot.id, userId: routine.userId, routineDayId: dayId,
                        position: exerciseSnapshot.position, ref: exerciseSnapshot.ref, input: exerciseSnapshot.input, now: now
                    ))
                }
            }
        }
        try modelContext.save()
    }

    private func clone(_ exercise: RoutineExercise, into dayId: UUID, now: Date) -> RoutineExercise {
        RoutineExercise(
            userId: exercise.userId, routineDayId: dayId, position: exercise.position,
            ref: exercise.ref ?? .catalog(exercise.exerciseId ?? ""),
            input: RoutineExerciseInput(
                targetSets: exercise.targetSets, targetRepsMin: exercise.targetRepsMin,
                targetRepsMax: exercise.targetRepsMax, targetRir: exercise.targetRir,
                supersetGroup: exercise.supersetGroup, restSeconds: exercise.restSeconds, notes: exercise.notes
            ),
            now: now
        )
    }
}
