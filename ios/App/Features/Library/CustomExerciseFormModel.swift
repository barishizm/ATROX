import DataKit
import Foundation
import Observation

/// Form state for creating or editing a custom exercise (P031).
@MainActor
@Observable
final class CustomExerciseFormModel {
    enum Mode: Equatable { case create, edit(UUID) }

    let mode: Mode
    private let userId: UUID
    private let repository: any CustomExerciseRepository

    var name = ""
    /// nil = no equipment.
    var equipment: String?
    var mechanic: String?
    var level = "beginner"
    var loadConvention = "total"
    var isUnilateral = false
    /// One step per line.
    var stepsText = ""
    private(set) var primaryMuscles: Set<String> = []
    private(set) var secondaryMuscles: Set<String> = []
    /// The catalog exercise this one is "similar to"; its scoring settings are inherited.
    private(set) var similar: ExerciseDetail?
    private(set) var isSaving = false
    private(set) var saveFailed = false
    /// Scoring kept as is when editing (or a new exercise without a "similar" pick).
    private var baseScoring: ScoringSettings = .none
    private var aliases: [String] = []

    init(userId: UUID, repository: any CustomExerciseRepository, editing snapshot: CustomExerciseSnapshot? = nil) {
        self.userId = userId
        self.repository = repository
        guard let snapshot else {
            mode = .create
            return
        }
        mode = .edit(snapshot.id)
        let input = snapshot.input
        name = input.name
        equipment = input.equipment
        mechanic = input.mechanic
        level = input.level
        loadConvention = input.scoring.loadConvention ?? "total"
        isUnilateral = input.isUnilateral
        stepsText = input.instructions.joined(separator: "\n")
        primaryMuscles = Set(input.primaryMuscles)
        secondaryMuscles = Set(input.secondaryMuscles)
        baseScoring = input.scoring
        aliases = input.aliases
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool {
        (1...ExerciseVocabulary.nameLimit).contains(trimmedName.count) && !primaryMuscles.isEmpty
    }

    // MARK: Muscles (a muscle is primary or secondary, never both)

    func setPrimary(_ muscles: Set<String>) {
        primaryMuscles = muscles
        secondaryMuscles.subtract(muscles)
    }

    func setSecondary(_ muscles: Set<String>) {
        secondaryMuscles = muscles.subtracting(primaryMuscles)
    }

    // MARK: Similar exercise

    /// Picks (or, with nil, removes) the catalog exercise to inherit scoring from. Empty fields are prefilled from
    /// it; ones the user already filled in are kept.
    func setSimilar(_ exercise: ExerciseDetail?) {
        similar = exercise
        guard let exercise else {
            baseScoring = .none
            return
        }
        baseScoring = exercise.scoring
        if let load = exercise.scoring.loadConvention { loadConvention = load }
        if primaryMuscles.isEmpty { setPrimary(Set(exercise.primaryMuscles)) }
        if secondaryMuscles.isEmpty { setSecondary(Set(exercise.secondaryMuscles)) }
        if equipment == nil { equipment = exercise.equipment }
        if mechanic == nil { mechanic = exercise.mechanic }
    }

    func input() -> CustomExerciseInput {
        var scoring = baseScoring
        scoring.loadConvention = loadConvention
        return CustomExerciseInput(
            name: trimmedName, aliases: aliases,
            instructions: stepsText.split(whereSeparator: \.isNewline).map(String.init),
            equipment: equipment, mechanic: mechanic, level: level,
            primaryMuscles: ExerciseVocabulary.muscles.filter(primaryMuscles.contains),
            secondaryMuscles: ExerciseVocabulary.muscles.filter(secondaryMuscles.contains),
            movementPattern: "other", isUnilateral: isUnilateral, scoring: scoring
        )
    }

    /// Saves; nil (and `saveFailed`) when invalid or the store failed.
    func save() async -> CustomExerciseSnapshot? {
        guard isValid, !isSaving else { return nil }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            switch mode {
            case .create: return try await repository.create(input(), userId: userId)
            case .edit(let id): return try await repository.update(id: id, with: input())
            }
        } catch {
            saveFailed = true
            return nil
        }
    }
}
