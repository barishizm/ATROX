import DataKit
import Foundation
import Observation

/// State of the routine editor (P033). Every edit is written to the local store right away (autosave); before each
/// edit the routine is remembered so `undo()` can put it back.
@MainActor
@Observable
final class RoutineEditorModel {
    enum LoadState: Equatable { case loading, loaded, missing, failed }

    static let undoLimit = 30

    let routineId: UUID
    let plan: RoutinePlanStore
    private(set) var loadState: LoadState = .loading
    private(set) var routine: RoutineSnapshot?
    private(set) var weeklySets: [MuscleSetCount] = []
    /// Set when the last edit failed; the screen shows an alert and clears it.
    var errorOccurred = false
    var languageCode = "en"

    private let repository: any RoutineRepository
    private let itemsProvider: @Sendable () async -> [ExerciseListItem]
    private var items: [String: ExerciseListItem] = [:]
    private var undoStack: [RoutineSnapshot] = []

    init(
        routineId: UUID, repository: any RoutineRepository, plan: RoutinePlanStore,
        itemsProvider: @escaping @Sendable () async -> [ExerciseListItem]
    ) {
        self.routineId = routineId
        self.repository = repository
        self.plan = plan
        self.itemsProvider = itemsProvider
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var isActive: Bool { plan.activeRoutineId == routineId }
    var emptyDays: [RoutineDaySnapshot] { routine.map(RoutineVolume.emptyDays(in:)) ?? [] }

    func load() async {
        let fetched = await itemsProvider()
        items = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        await reload()
    }

    func day(_ id: UUID) -> RoutineDaySnapshot? { routine?.days.first { $0.id == id } }

    func item(for ref: ExerciseRef) -> ExerciseListItem? { items[Self.id(of: ref)] }

    func name(of ref: ExerciseRef) -> String { item(for: ref)?.name(languageCode: languageCode) ?? "—" }

    static func id(of ref: ExerciseRef) -> String {
        switch ref {
        case .catalog(let id): id
        case .custom(let id): id.uuidString
        }
    }

    static func ref(fromItemID id: String) -> ExerciseRef {
        UUID(uuidString: id).map(ExerciseRef.custom) ?? .catalog(id)
    }

    /// The letter shown on superset members ("A", "B"…): groups are lettered in the order they appear in the day.
    func supersetLetter(of exercise: RoutineExerciseSnapshot, in day: RoutineDaySnapshot) -> String? {
        guard let group = exercise.input.supersetGroup else { return nil }
        var order: [Int] = []
        for member in day.exercises {
            if let value = member.input.supersetGroup, !order.contains(value) { order.append(value) }
        }
        guard let index = order.firstIndex(of: group) else { return nil }
        return String(UnicodeScalar(UInt8(65 + index % 26)))
    }

    // MARK: Edits

    func rename(_ name: String, notes: String?) async {
        guard let routine, name.trimmingCharacters(in: .whitespacesAndNewlines) != routine.name || notes != routine.notes else { return }
        await edit { try await $0.update(id: routineId, name: name, notes: notes) }
    }

    func addDay(name: String) async -> UUID? {
        var created: UUID?
        await edit { created = try await $0.addDay(routineId: routineId, name: name).id }
        return created
    }

    func renameDay(_ id: UUID, to name: String) async {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != day(id)?.name else { return }
        await edit { try await $0.renameDay(id: id, to: name) }
    }

    func moveDays(from source: IndexSet, to destination: Int) async {
        guard let days = routine?.days, let from = source.first else { return }
        await edit { try await $0.moveDay(id: days[from].id, to: from < destination ? destination - 1 : destination) }
    }

    func deleteDay(_ id: UUID) async { await edit { try await $0.deleteDay(id: id) } }

    func duplicateDay(_ id: UUID, name: String) async { await edit { _ = try await $0.duplicateDay(id: id, name: name) } }

    func addExercises(dayId: UUID, itemIDs: [String]) async {
        await edit { repo in
            for id in itemIDs {
                try await repo.addExercise(dayId: dayId, ref: Self.ref(fromItemID: id), input: Self.defaultInput)
            }
        }
    }

    func update(_ exercise: RoutineExerciseSnapshot, with input: RoutineExerciseInput) async {
        guard input != exercise.input else { return }
        await edit { try await $0.updateExercise(id: exercise.id, with: input) }
    }

    /// `source` / `destination` follow `onMove` of a `List` over the day's exercises.
    func moveExercises(dayId: UUID, from source: IndexSet, to destination: Int) async {
        guard let exercises = day(dayId)?.exercises, let from = source.first else { return }
        await edit { try await $0.moveExercise(id: exercises[from].id, to: from < destination ? destination - 1 : destination) }
    }

    func deleteExercise(_ id: UUID) async { await edit { try await $0.deleteExercise(id: id) } }

    func duplicateExercise(_ id: UUID) async { await edit { _ = try await $0.duplicateExercise(id: id) } }

    func makeSuperset(_ ids: [UUID]) async { await edit { try await $0.setSuperset(exerciseIds: ids) } }

    func leaveSuperset(_ id: UUID) async { await edit { try await $0.clearSuperset(exerciseId: id) } }

    func undo() async {
        guard let previous = undoStack.popLast() else { return }
        do {
            try await repository.restore(previous)
            await reload()
        } catch {
            errorOccurred = true
        }
    }

    // MARK: Plan

    func setActive(_ active: Bool) { plan.setActive(active ? routineId : nil) }

    func assign(dayId: UUID?, toWeekday weekday: Int) { plan.assign(dayId: dayId, toWeekday: weekday) }

    /// The assignment of a weekday, as far as this routine is concerned.
    enum WeekdayPlan: Hashable {
        case rest
        case day(UUID)
        /// A day of another program (or one that no longer exists).
        case elsewhere
    }

    func weekdayPlan(_ weekday: Int) -> WeekdayPlan {
        guard let id = plan.dayByWeekday[weekday] else { return .rest }
        return day(id) != nil ? .day(id) : .elsewhere
    }

    // MARK: Internals

    /// "Day 3" / "Gün 3": the name a day gets when the user leaves the field empty.
    static func defaultDayName(_ number: Int, languageCode: String) -> String {
        languageCode == "tr" ? "Gün \(number)" : "Day \(number)"
    }

    static let defaultInput = RoutineExerciseInput(targetSets: 3, targetRepsMin: 8, targetRepsMax: 12, restSeconds: 90)

    private func edit(_ operation: (any RoutineRepository) async throws -> Void) async {
        let before = routine
        do {
            try await operation(repository)
            if let before {
                undoStack.append(before)
                if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
            }
            await reload()
        } catch {
            errorOccurred = true
            await reload()
        }
    }

    private func reload() async {
        do {
            guard let loaded = try await repository.routine(id: routineId) else {
                loadState = .missing
                return
            }
            routine = loaded
            weeklySets = RoutineVolume.weeklySets(in: loaded) { [items] ref in
                items[Self.id(of: ref)].map { ($0.primaryMuscles, $0.secondaryMuscles) }
            }
            loadState = .loaded
        } catch {
            if routine == nil { loadState = .failed } else { errorOccurred = true }
        }
    }
}
