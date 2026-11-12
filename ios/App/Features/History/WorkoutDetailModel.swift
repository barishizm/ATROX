import DataKit
import Foundation
import Observation
import StrengthKit

/// One finished workout in the history (P042): shows its exercises, sets and records, and edits or deletes them. Every
/// edit goes through `WorkoutHistoryEditor`, so records are rebuilt and the workout is re-read from the store.
@MainActor
@Observable
final class WorkoutDetailModel {
    let id: UUID
    let context: HistoryContext
    private(set) var workout: WorkoutSnapshot?
    private(set) var isMissing = false
    private(set) var isLoading = true
    private(set) var names: [String: String] = [:]
    /// Records each set of this workout currently holds, best first.
    private(set) var recordKinds: [UUID: [RecordKind]] = [:]
    var isEditing = false
    /// Localization key of the last failed action, shown once.
    var errorKey: String?
    /// Set after a successful delete: the screen closes.
    private(set) var wasDeleted = false

    @ObservationIgnored private let events: HistoryEvents

    init(id: UUID, context: HistoryContext, events: HistoryEvents) {
        self.id = id
        self.context = context
        self.events = events
    }

    // MARK: Loading

    func load() async {
        names = await context.loadNames()
        await reload()
        isLoading = false
    }

    func reload() async {
        do {
            workout = try await context.workouts.workout(id: id)
            isMissing = workout == nil
            await loadRecords()
        } catch {
            errorKey = "history.error"
        }
    }

    private func loadRecords() async {
        guard let workout else { return }
        let mine = Set(workout.exercises.flatMap(\.sets).map(\.id))
        var found: [UUID: [RecordKind]] = [:]
        for ref in Set(workout.exercises.map(\.ref)) {
            for mark in (try? await context.records.current(userId: context.userId, ref: ref)) ?? []
            where mine.contains(mark.setId) {
                if let kind = RecordKind(rawValue: mark.metric.rawValue) { found[mark.setId, default: []].append(kind) }
            }
        }
        recordKinds = found.mapValues { $0.sorted { Self.rank($0) < Self.rank($1) } }
    }

    static func rank(_ kind: RecordKind) -> Int {
        switch kind {
        case .weight: 0
        case .e1rm: 1
        case .volume: 2
        case .reps: 3
        }
    }

    // MARK: Display

    func name(of ref: ExerciseRef) -> String { names[HistoryContext.id(of: ref)] ?? "—" }

    var volumeText: String { workout.map { context.weightText(WorkoutSummary.volume(of: $0)) } ?? "" }
    var durationText: String { HistoryContext.durationText(workout?.duration ?? 0) }

    /// Editable text of a weight in the display unit, e.g. "82.5".
    func editableWeight(_ kg: Double) -> String {
        context.unit.value(fromKilograms: kg).formatted(.number.precision(.fractionLength(0...2)).locale(context.locale).grouping(.never))
    }

    // MARK: Editing

    func saveDetails(name: String, notes: String) async {
        await run { try await self.context.editor.updateDetails(workoutId: self.id, name: name, notes: notes) }
    }

    func setRating(_ rating: Int?) async {
        await run { try await self.context.editor.setRating(workoutId: self.id, rating: rating) }
    }

    /// Saves a set from the edit sheet; false (nothing written) when the text is not a valid weight and rep count.
    func saveSet(_ setId: UUID, weightText: String, repsText: String, type: SetType) async -> Bool {
        let trimmedWeight = weightText.trimmingCharacters(in: .whitespaces)
        let weight = trimmedWeight.isEmpty ? 0 : WeightFormat.kilograms(from: trimmedWeight, unit: context.unit, locale: context.locale)
        let reps = Int(repsText.trimmingCharacters(in: .whitespaces) )
        guard let weight, let reps, (0...100).contains(reps), weight <= 1000 else {
            errorKey = "history.error.invalidSet"
            return false
        }
        let kg = (weight * 1000).rounded() / 1000
        return await run { try await self.context.editor.editSet(workoutId: self.id, setId: setId) { input in
            input.weightKg = kg
            input.reps = reps
            input.setType = type
        } }
    }

    func addSet(to exerciseId: UUID) async {
        await run { try await self.context.editor.addSet(workoutId: self.id, exerciseId: exerciseId) }
    }

    func removeSet(_ setId: UUID) async {
        await run { try await self.context.editor.removeSet(workoutId: self.id, setId: setId) }
    }

    func addExercise(_ ref: ExerciseRef) async {
        await run { try await self.context.editor.addExercise(workoutId: self.id, ref: ref) }
    }

    func removeExercise(_ exerciseId: UUID) async {
        await run { try await self.context.editor.removeExercise(workoutId: self.id, exerciseId: exerciseId) }
    }

    /// Deletes the workout; the history list offers the undo.
    func delete(title: String) async {
        do {
            try await context.editor.delete(workoutId: id)
            events.undo = HistoryEvents.PendingUndo(id: id, title: title)
            events.changed()
            wasDeleted = true
        } catch {
            errorKey = "history.error"
        }
    }

    /// Turns the workout into a one-day program.
    @discardableResult
    func convertToRoutine(name: String, dayName: String) async -> Bool {
        guard let workout else { return false }
        do {
            try await RoutineConverter.convert(
                workout, name: name, dayName: dayName, userId: context.userId, routines: context.routines
            )
            return true
        } catch {
            errorKey = "history.error"
            return false
        }
    }

    @discardableResult
    private func run(_ work: () async throws -> some Any) async -> Bool {
        do {
            _ = try await work()
            events.changed()
            await reload()
            return true
        } catch {
            errorKey = "history.error"
            return false
        }
    }
}
