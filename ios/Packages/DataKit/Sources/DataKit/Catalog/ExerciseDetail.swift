import Foundation
import SwiftData

/// What the detail screen explains about how an exercise is scored (P031). Pure function of the scoring settings.
public enum ScoreNote: String, Sendable, Equatable {
    /// Not scored at all (`scoring_type = none`), e.g. stretches, cardio and unrated custom exercises.
    case notScored
    /// Load differs between machine brands, so the score has low confidence.
    case machine
    /// Rated by repetitions only.
    case repsOnly
    /// Rated by hold / work time.
    case time
    /// Bodyweight plus added load.
    case bodyweightLoaded
    /// Estimated from a related lift with low-confidence ratio (grade C).
    case lowConfidence

    public static func note(for scoring: ScoringSettings, equipment: String?) -> ScoreNote? {
        switch scoring.type {
        case "none": return .notScored
        case "reps_only": return .repsOnly
        case "time": return .time
        default: break
        }
        if equipment == "machine" || scoring.loadConvention == "machine_stack" { return .machine }
        if scoring.ratioConfidence == "C" { return .lowConfidence }
        if scoring.type == "bodyweight_loaded" { return .bodyweightLoaded }
        return nil
    }
}

/// Everything the detail screen shows, as a `Sendable` value so it can be built off the main actor.
public struct ExerciseDetail: Sendable, Equatable, Identifiable {
    public let id: String
    public let isCustom: Bool
    public let nameEn: String
    public let nameTr: String
    public let instructionsEn: [String]
    public let instructionsTr: [String]
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let equipment: String?
    public let mechanic: String?
    public let level: String
    public let scoring: ScoringSettings
    /// Full-size image file names (start and end frame); empty for custom exercises.
    public let imagePaths: [String]
    public let isUnilateral: Bool

    public init(
        id: String, isCustom: Bool = false, nameEn: String, nameTr: String, instructionsEn: [String] = [],
        instructionsTr: [String] = [], primaryMuscles: [String], secondaryMuscles: [String] = [],
        equipment: String? = nil, mechanic: String? = nil, level: String = "beginner",
        scoring: ScoringSettings = .none, imagePaths: [String] = [], isUnilateral: Bool = false
    ) {
        self.id = id
        self.isCustom = isCustom
        self.nameEn = nameEn
        self.nameTr = nameTr
        self.instructionsEn = instructionsEn
        self.instructionsTr = instructionsTr
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.level = level
        self.scoring = scoring
        self.imagePaths = imagePaths
        self.isUnilateral = isUnilateral
    }

    public init(_ exercise: Exercise) {
        self.init(
            id: exercise.id, nameEn: exercise.nameEn, nameTr: exercise.nameTr,
            instructionsEn: exercise.instructionsEn, instructionsTr: exercise.instructionsTr,
            primaryMuscles: exercise.primaryMuscles, secondaryMuscles: exercise.secondaryMuscles,
            equipment: exercise.equipment, mechanic: exercise.mechanic, level: exercise.level,
            scoring: ScoringSettings(exercise), imagePaths: exercise.imagePaths, isUnilateral: exercise.isUnilateral
        )
    }

    public init(_ custom: CustomExercise) {
        let snapshot = custom.snapshot.input
        self.init(
            id: custom.id.uuidString, isCustom: true, nameEn: snapshot.name, nameTr: snapshot.name,
            instructionsEn: snapshot.instructions, instructionsTr: snapshot.instructions,
            primaryMuscles: snapshot.primaryMuscles, secondaryMuscles: snapshot.secondaryMuscles,
            equipment: snapshot.equipment, mechanic: snapshot.mechanic, level: snapshot.level,
            scoring: snapshot.scoring, isUnilateral: snapshot.isUnilateral
        )
    }

    public func name(languageCode: String) -> String { languageCode == "tr" ? nameTr : nameEn }

    /// Steps in the user's language; falls back to the other language when the translation is missing.
    public func instructions(languageCode: String) -> [String] {
        let preferred = languageCode == "tr" ? instructionsTr : instructionsEn
        return preferred.isEmpty ? (languageCode == "tr" ? instructionsEn : instructionsTr) : preferred
    }

    public var scoreNote: ScoreNote? { ScoreNote.note(for: scoring, equipment: equipment) }
    public var isScorable: Bool { scoring.type != "none" }
    /// The thumbnail-sized pair shown while the full images load.
    public var frames: [String] { Array(imagePaths.prefix(2)) }

    /// Looks the exercise up by id: a catalog slug or a custom exercise UUID. nil when it does not exist
    /// (or was deleted / archived-and-gone).
    public static func load(id: String, in container: ModelContainer) throws -> ExerciseDetail? {
        let context = ModelContext(container)
        if let uuid = UUID(uuidString: id) {
            var custom = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.id == uuid && $0.deletedAt == nil })
            custom.fetchLimit = 1
            return try context.fetch(custom).first.map(ExerciseDetail.init)
        }
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map(ExerciseDetail.init)
    }
}
