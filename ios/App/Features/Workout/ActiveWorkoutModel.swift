import DataKit
import Foundation
import Observation

/// Screen state of the active workout (P036): turns `WorkoutSession` snapshots into display rows and drives the
/// numeric keypad. Every change is written through the session (and so to SwiftData) immediately.
@MainActor
@Observable
final class ActiveWorkoutModel {
    struct SetRow: Identifiable, Equatable {
        let id: UUID
        let exerciseId: UUID
        let type: SetType
        /// "1", "2" … for working sets; "W" / "D" / "F" for warm-up, drop and failure sets.
        let badge: String
        let weightText: String
        let repsText: String
        /// "Last time" for this set, e.g. "80 × 8"; nil when there is no history.
        let previousText: String?
        let rir: Int?
        let isCompleted: Bool
    }

    struct ExerciseCard: Identifiable, Equatable {
        let id: UUID
        let ref: ExerciseRef
        let name: String
        let notes: String?
        let supersetGroup: Int?
        let rows: [SetRow]
    }

    /// A catalog or custom exercise with its movement pattern (for "similar" suggestions).
    struct CatalogEntry: Sendable {
        let item: ExerciseListItem
        let pattern: String?
        /// "compound" / "isolation" (catalog); decides the default rest.
        var mechanic: String?
    }

    struct Editing: Equatable {
        let setId: UUID
        var keypad: WorkoutKeypad
    }

    let session: WorkoutSession
    var unit: WeightUnit
    var showsRir: Bool
    /// Starts a rest countdown when a set is completed.
    var autoStartsRest: Bool
    let rest: RestTimerController
    private(set) var editing: Editing?
    /// Localization key of the last failed action, shown once.
    var errorKey: String?

    @ObservationIgnored private let itemsProvider: @Sendable () async -> [CatalogEntry]
    @ObservationIgnored private var items: [String: ExerciseListItem] = [:]
    @ObservationIgnored private var patterns: [String: String] = [:]
    @ObservationIgnored private var mechanics: [String: String] = [:]
    @ObservationIgnored let languageCode: String
    @ObservationIgnored let decimalSeparator: String

    init(
        session: WorkoutSession, unit: WeightUnit, showsRir: Bool = true, autoStartsRest: Bool = true,
        rest: RestTimerController? = nil, languageCode: String = "en",
        decimalSeparator: String = ".", itemsProvider: @escaping @Sendable () async -> [CatalogEntry]
    ) {
        self.session = session
        self.unit = unit
        self.showsRir = showsRir
        self.autoStartsRest = autoStartsRest
        self.rest = rest ?? RestTimerController(notifications: FakeNotificationService(status: .denied))
        self.languageCode = languageCode
        self.decimalSeparator = decimalSeparator
        self.itemsProvider = itemsProvider
    }

    func load() async {
        let fetched = await itemsProvider()
        items = Dictionary(fetched.map { ($0.item.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        patterns = Dictionary(fetched.compactMap { entry in entry.pattern.map { (entry.item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        mechanics = Dictionary(fetched.compactMap { entry in entry.mechanic.map { (entry.item.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Display

    var isActive: Bool { session.phase == .active }
    var plateStep: Double { PlateRounding.step(for: unit) }

    var title: String { session.workout?.name ?? "" }

    var cards: [ExerciseCard] {
        guard let workout = session.workout, session.phase == .active else { return [] }
        return workout.exercises.map { exercise in
            let last = session.previous[exercise.id] ?? []
            var working = 0
            let rows = exercise.sets.enumerated().map { index, entry -> SetRow in
                if entry.input.setType == .working { working += 1 }
                return SetRow(
                    id: entry.id, exerciseId: exercise.id, type: entry.input.setType,
                    badge: Self.badge(entry.input.setType, workingNumber: working),
                    weightText: weightText(kg: entry.input.weightKg), repsText: String(entry.input.reps),
                    previousText: index < last.count ? previousText(last[index]) : nil,
                    rir: entry.input.rir, isCompleted: entry.input.isCompleted
                )
            }
            return ExerciseCard(
                id: exercise.id, ref: exercise.ref, name: name(of: exercise.ref), notes: exercise.notes,
                supersetGroup: exercise.supersetGroup, rows: rows
            )
        }
    }

    var completedSetCount: Int {
        session.workout?.exercises.flatMap(\.sets).filter(\.input.isCompleted).count ?? 0
    }

    var totalSetCount: Int { session.workout?.exercises.flatMap(\.sets).count ?? 0 }

    func name(of ref: ExerciseRef) -> String {
        items[Self.id(of: ref)]?.name(languageCode: languageCode) ?? "—"
    }

    func item(of ref: ExerciseRef) -> ExerciseListItem? { items[Self.id(of: ref)] }

    static func id(of ref: ExerciseRef) -> String {
        switch ref {
        case .catalog(let id): id
        case .custom(let id): id.uuidString
        }
    }

    static func badge(_ type: SetType, workingNumber: Int) -> String {
        switch type {
        case .working: String(workingNumber)
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }

    /// Stored kg → text in the display unit, without the unit symbol ("82.5").
    func weightText(kg: Double) -> String {
        WorkoutKeypad.format(unit.value(fromKilograms: kg), field: .weight)
            .replacingOccurrences(of: ".", with: decimalSeparator)
    }

    func previousText(_ input: SetInput) -> String {
        "\(weightText(kg: input.weightKg)) × \(input.reps)"
    }

    // MARK: Completing

    /// Completes a set exactly as shown (the pre-filled values are accepted); completing a done set undoes it.
    func toggleComplete(_ setId: UUID) async {
        await commit()
        editing = nil
        await run {
            if self.session.set(setId)?.input.isCompleted == true {
                try await self.session.uncompleteSet(setId)
            } else {
                try await self.session.completeSet(setId)
                await self.startRestAfter(setId)
            }
        }
    }

    // MARK: Rest

    /// Seconds of rest after a set of this workout exercise: the routine's value, else by movement type.
    func restSeconds(forExercise exerciseId: UUID) -> Int {
        let ref = session.exercise(exerciseId)?.ref
        let mechanic = ref.flatMap { mechanics[Self.id(of: $0)] }
        return RestDefaults.seconds(program: session.programRest[exerciseId], mechanic: mechanic)
    }

    /// Starts the countdown after a completed set, unless that was the last open set of the workout.
    private func startRestAfter(_ setId: UUID) async {
        guard autoStartsRest, nextOpenSet(after: setId) != nil,
              let exercise = session.workout?.exercises.first(where: { $0.sets.contains { $0.id == setId } })
        else { return }
        await rest.start(
            seconds: restSeconds(forExercise: exercise.id),
            title: String(localized: "workout.rest.done.title"), body: String(localized: "workout.rest.done.body")
        )
    }

    // MARK: Keypad

    func beginEditing(_ setId: UUID, field: WorkoutKeypad.Field) async {
        await commit()
        guard let input = session.set(setId)?.input else { return }
        let value = field == .weight ? unit.value(fromKilograms: input.weightKg) : Double(input.reps)
        editing = Editing(setId: setId, keypad: WorkoutKeypad(field: field, value: value))
    }

    func press(digit: Int) { editing?.keypad.digit(digit) }
    func pressDecimal() { editing?.keypad.decimal() }
    func pressBackspace() { editing?.keypad.backspace() }

    func pressStep(_ direction: Int) {
        guard let field = editing?.keypad.field else { return }
        editing?.keypad.step(direction, by: field == .weight ? plateStep : 1)
    }

    /// "Same as before": fills the field with this set's value from last time (or the previous set of this workout).
    func pressSameAsPrevious() {
        guard let editing, let reference = reference(for: editing.setId) else { return }
        let value = editing.keypad.field == .weight ? unit.value(fromKilograms: reference.weightKg) : Double(reference.reps)
        self.editing?.keypad.replace(with: value)
    }

    /// The set whose values "same as before" copies: last time's set at the same index, else the set above.
    func reference(for setId: UUID) -> SetInput? {
        guard let workout = session.workout else { return nil }
        for exercise in workout.exercises {
            guard let index = exercise.sets.firstIndex(where: { $0.id == setId }) else { continue }
            let last = session.previous[exercise.id] ?? []
            if index < last.count { return last[index] }
            return index > 0 ? exercise.sets[index - 1].input : nil
        }
        return nil
    }

    /// Saves the typed value and moves on: weight → reps of the same set → weight of the next open set → done.
    func advance() async {
        guard let current = editing else { return }
        await commit()
        switch current.keypad.field {
        case .weight:
            await beginEditing(current.setId, field: .reps)
        case .reps:
            if let next = nextOpenSet(after: current.setId) {
                await beginEditing(next, field: .weight)
            } else {
                editing = nil
            }
        }
    }

    func dismissKeypad() async {
        await commit()
        editing = nil
    }

    func nextOpenSet(after setId: UUID) -> UUID? {
        let all = (session.workout?.exercises ?? []).flatMap(\.sets)
        guard let index = all.firstIndex(where: { $0.id == setId }) else { return nil }
        return all[(index + 1)...].first { !$0.input.isCompleted }?.id
    }

    /// Writes the typed number to the set. An empty field leaves the value as it was.
    private func commit() async {
        guard let editing, let typed = editing.keypad.value, session.set(editing.setId) != nil else { return }
        let setId = editing.setId
        switch editing.keypad.field {
        case .weight:
            let kg = (unit.kilograms(from: typed) * 1000).rounded() / 1000
            await run { try await self.session.setWeight(setId, kg: kg) }
        case .reps:
            await run { try await self.session.setReps(setId, reps: Int(typed)) }
        }
    }

    // MARK: Sets and exercises

    func setType(_ setId: UUID, _ type: SetType) async {
        await run { try await self.session.setType(setId, to: type) }
    }

    func setRir(_ setId: UUID, _ rir: Int?) async {
        await run { try await self.session.setRir(setId, rir: rir) }
    }

    func removeSet(_ setId: UUID) async {
        if editing?.setId == setId { editing = nil }
        await run { try await self.session.removeSet(setId) }
    }

    func addSet(to exerciseId: UUID) async {
        await run { _ = try await self.session.addSet(to: exerciseId) }
    }

    func addExercise(_ ref: ExerciseRef) async {
        await run { _ = try await self.session.addExercise(ref) }
    }

    func replaceExercise(_ exerciseId: UUID, with ref: ExerciseRef) async {
        editing = nil
        await run { _ = try await self.session.replaceExercise(exerciseId, with: ref) }
    }

    func removeExercise(_ exerciseId: UUID) async {
        editing = nil
        await run { try await self.session.removeExercise(exerciseId) }
    }

    func setNotes(_ exerciseId: UUID, _ notes: String) async {
        await run { try await self.session.setExerciseNotes(exerciseId, notes: notes) }
    }

    /// Catalog exercises that train the same movement and main muscle as `ref` (not already in the workout).
    func similarExercises(to ref: ExerciseRef, limit: Int = 8) -> [ExerciseListItem] {
        guard let source = item(of: ref), let pattern = patterns[Self.id(of: ref)] else { return [] }
        let inWorkout = Set((session.workout?.exercises ?? []).map { Self.id(of: $0.ref) })
        return items.values
            .filter { candidate in
                !candidate.isCustom && !inWorkout.contains(candidate.id)
                    && candidate.primaryMuscle == source.primaryMuscle && patterns[candidate.id] == pattern
            }
            .sorted { $0.name(languageCode: languageCode) < $1.name(languageCode: languageCode) }
            .prefix(limit).map { $0 }
    }

    // MARK: End

    func finish() async -> WorkoutSession.FinishResult? {
        await commit()
        editing = nil
        await rest.skip()
        do {
            return try await session.finish()
        } catch {
            errorKey = "workout.error.generic"
            return nil
        }
    }

    func cancel() async {
        editing = nil
        await rest.skip()
        await run { try await self.session.cancel() }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        do { try await work() } catch { errorKey = "workout.error.generic" }
    }
}
