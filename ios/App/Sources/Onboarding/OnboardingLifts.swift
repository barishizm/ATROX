import DataKit
import Foundation
import StrengthKit

/// One of the four basic-lift cards. `skipped` = "I don't know / I don't do this".
struct LiftEntry: Codable, Equatable, Sendable {
    var lift: BasicLift
    var weightKg: Double?
    var reps: Int?
    var skipped = false

    /// A set the score can be computed from.
    var isComplete: Bool { !skipped && (weightKg ?? 0) > 0 && (reps ?? 0) >= 1 }
}

enum OnboardingLifts {
    static let order: [BasicLift] = [.benchPress, .squat, .deadlift, .overheadPress]
    static let repsRange = 1...30
    static let maximumWeightKg = 500.0

    /// Barbell for gym/barbell access; dumbbell alternatives otherwise (bodyweight-only users may still know a pair).
    static func implement(for equipment: EquipmentAccess?) -> LiftImplement {
        switch equipment {
        case .fullGym, .homeBarbell: .barbell
        case .homeDumbbell, .bodyweightOnly, nil: .dumbbell
        }
    }

    static let defaultReps = 5

    static func blank() -> [LiftEntry] { order.map { LiftEntry(lift: $0, reps: defaultReps) } }
}

/// What the result screen shows for one lift.
struct LiftResult: Equatable, Identifiable, Sendable {
    let lift: BasicLift
    let score: Double
    var id: BasicLift { lift }
}

/// Turns the sets reported in onboarding into the single finished workout (source = onboarding) kept in the history.
enum OnboardingWorkout {
    /// Catalog exercise behind each basic lift. Dumbbell sets use the one-dumbbell weight (`LiftSet` convention).
    static func catalogId(lift: BasicLift, implement: LiftImplement) -> String {
        switch (lift, implement) {
        case (.benchPress, .barbell): "barbell-bench-press-medium-grip"
        case (.benchPress, .dumbbell): "dumbbell-bench-press"
        case (.squat, .barbell): "barbell-squat"
        case (.squat, .dumbbell): "dumbbell-squat"
        case (.deadlift, .barbell): "barbell-deadlift"
        case (.deadlift, .dumbbell): "stiff-legged-dumbbell-deadlift"
        case (.overheadPress, .barbell): "barbell-shoulder-press"
        case (.overheadPress, .dumbbell): "dumbbell-shoulder-press"
        }
    }

    /// `nil` when there is nothing to store (every card skipped).
    static func draft(from sets: [LiftSet], at date: Date) -> WorkoutDraft? {
        guard !sets.isEmpty else { return nil }
        let exercises = sets.map { set in
            WorkoutExerciseDraft(
                ref: .catalog(catalogId(lift: set.lift, implement: set.implement)),
                sets: [SetInput(weightKg: set.weightKg, reps: set.reps, setType: .working, isCompleted: true)]
            )
        }
        return WorkoutDraft(startedAt: date, endedAt: date, source: .onboarding, exercises: exercises)
    }
}
