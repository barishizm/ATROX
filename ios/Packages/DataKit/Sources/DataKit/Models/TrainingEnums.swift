import Foundation

/// What a routine/workout/PR row points at: a catalog exercise (`exercises.id`) or the user's own exercise.
/// The server stores this as two nullable columns with a "exactly one" CHECK; the enum makes that impossible to break.
public enum ExerciseRef: Sendable, Hashable {
    case catalog(String)
    case custom(UUID)

    init?(exerciseId: String?, customExerciseId: UUID?) {
        switch (exerciseId, customExerciseId) {
        case let (id?, nil): self = .catalog(id)
        case let (nil, id?): self = .custom(id)
        default: return nil
        }
    }

    var catalogId: String? {
        if case .catalog(let id) = self { id } else { nil }
    }

    var customId: UUID? {
        if case .custom(let id) = self { id } else { nil }
    }
}

public enum SetType: String, Sendable, Codable, CaseIterable {
    case warmup, working, drop, failure
}

public enum WorkoutSource: String, Sendable, Codable, CaseIterable {
    /// Started from an empty workout.
    case manual
    /// Started from a routine day.
    case routine
    /// The sets the user reported while onboarding (P021).
    case onboarding
    /// Imported from another app (later).
    case imported = "import"
}

public enum RecordKind: String, Sendable, Codable, CaseIterable {
    case weight, reps, e1rm, volume
}
