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

/// Temporary home of the onboarding sets until workouts exist.
/// TODO(P032): save these as one Workout with source = onboarding and delete this store.
protocol OnboardingSetStore: Sendable {
    func load(userId: UUID) -> [LiftSet]
    func save(_ sets: [LiftSet], userId: UUID)
}

/// `UserDefaults` is documented as thread-safe, hence `@unchecked`.
struct UserDefaultsOnboardingSetStore: OnboardingSetStore, @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ userId: UUID) -> String { "onboarding.sets.\(userId.uuidString)" }

    func load(userId: UUID) -> [LiftSet] {
        guard let data = defaults.data(forKey: key(userId)) else { return [] }
        return (try? JSONDecoder().decode([LiftSet].self, from: data)) ?? []
    }

    func save(_ sets: [LiftSet], userId: UUID) {
        guard let data = try? JSONEncoder().encode(sets) else { return }
        defaults.set(data, forKey: key(userId))
    }
}
