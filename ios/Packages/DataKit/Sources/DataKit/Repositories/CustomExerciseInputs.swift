import Foundation

/// Scoring parameters of an exercise. A custom exercise starts with `.none`; "similar to" copies the catalog
/// exercise's settings so the Strength Score treats it the same way.
public struct ScoringSettings: Sendable, Equatable {
    public static let none = ScoringSettings()

    public var type: String
    public var anchorLift: String?
    public var loadConvention: String?
    public var ratio: Double?
    public var tau: Double?
    public var ratioConfidence: String?
    public var bwFraction: Double?

    public init(
        type: String = "none", anchorLift: String? = nil, loadConvention: String? = nil, ratio: Double? = nil,
        tau: Double? = nil, ratioConfidence: String? = nil, bwFraction: Double? = nil
    ) {
        self.type = type
        self.anchorLift = anchorLift
        self.loadConvention = loadConvention
        self.ratio = ratio
        self.tau = tau
        self.ratioConfidence = ratioConfidence
        self.bwFraction = bwFraction
    }

    init(_ exercise: Exercise) {
        self.init(
            type: exercise.scoringTypeRaw, anchorLift: exercise.anchorLift, loadConvention: exercise.loadConvention,
            ratio: exercise.ratio, tau: exercise.tau, ratioConfidence: exercise.ratioConfidence,
            bwFraction: exercise.bwFraction
        )
    }
}

/// Allowed values, identical to the CHECK constraints of `public.custom_exercises` (schema_4).
public enum ExerciseVocabulary {
    public static let muscles = [
        "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
        "lats", "lower_back", "middle_back", "neck", "quadriceps", "shoulders", "traps", "triceps",
    ]
    public static let equipment = [
        "barbell", "dumbbell", "kettlebell", "machine", "cable", "bands", "body_only", "ez_bar", "exercise_ball",
        "foam_roll", "medicine_ball", "other",
    ]
    public static let mechanics = ["compound", "isolation"]
    public static let levels = ["beginner", "intermediate", "expert"]
    public static let loadConventions = ["total", "per_hand", "per_side", "machine_stack", "bodyweight_plus"]
    public static let nameLimit = 200
}

public struct CustomExerciseInput: Sendable, Equatable {
    public var name: String
    public var aliases: [String]
    public var instructions: [String]
    /// nil = no equipment (bodyweight).
    public var equipment: String?
    public var mechanic: String?
    public var level: String
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var movementPattern: String
    public var isUnilateral: Bool
    public var scoring: ScoringSettings

    public init(
        name: String, aliases: [String] = [], instructions: [String] = [], equipment: String? = nil,
        mechanic: String? = nil, level: String = "beginner", primaryMuscles: [String],
        secondaryMuscles: [String] = [], movementPattern: String = "other", isUnilateral: Bool = false,
        scoring: ScoringSettings = .none
    ) {
        self.name = name
        self.aliases = aliases
        self.instructions = instructions
        self.equipment = equipment
        self.mechanic = mechanic
        self.level = level
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern
        self.isUnilateral = isUnilateral
        self.scoring = scoring
    }

    /// Trims text and drops empty entries; throws the first invalid field.
    func validated() throws -> CustomExerciseInput {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.aliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        copy.instructions = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard (1...ExerciseVocabulary.nameLimit).contains(copy.name.count) else { throw DataError.invalidValue("name") }
        guard !primaryMuscles.isEmpty, primaryMuscles.allSatisfy(ExerciseVocabulary.muscles.contains) else {
            throw DataError.invalidValue("primaryMuscles")
        }
        guard secondaryMuscles.allSatisfy(ExerciseVocabulary.muscles.contains) else {
            throw DataError.invalidValue("secondaryMuscles")
        }
        if let equipment, !ExerciseVocabulary.equipment.contains(equipment) { throw DataError.invalidValue("equipment") }
        if let mechanic, !ExerciseVocabulary.mechanics.contains(mechanic) { throw DataError.invalidValue("mechanic") }
        guard ExerciseVocabulary.levels.contains(level) else { throw DataError.invalidValue("level") }
        if let load = scoring.loadConvention, !ExerciseVocabulary.loadConventions.contains(load) {
            throw DataError.invalidValue("loadConvention")
        }
        copy.secondaryMuscles = secondaryMuscles.filter { !primaryMuscles.contains($0) }
        return copy
    }
}

public struct CustomExerciseSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let syncState: SyncState
    public let input: CustomExerciseInput
}

extension CustomExercise {
    var snapshot: CustomExerciseSnapshot {
        CustomExerciseSnapshot(
            id: id, userId: userId, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt,
            syncState: syncState,
            input: CustomExerciseInput(
                name: name, aliases: aliases, instructions: instructions, equipment: equipment,
                mechanic: mechanic, level: level, primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles, movementPattern: movementPattern, isUnilateral: isUnilateral,
                scoring: ScoringSettings(
                    type: scoringTypeRaw, anchorLift: anchorLift, loadConvention: loadConvention, ratio: ratio,
                    tau: tau, ratioConfidence: ratioConfidence, bwFraction: bwFraction
                )
            )
        )
    }
}
