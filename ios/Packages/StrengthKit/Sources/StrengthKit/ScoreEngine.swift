import Foundation

/// The four basic lifts scored during onboarding.
public enum BasicLift: String, Sendable, Codable, CaseIterable {
    case benchPress, squat, deadlift, overheadPress
}

/// What the lifter used. For `.dumbbell`, `LiftSet.weightKg` is the weight of ONE dumbbell (two are used).
public enum LiftImplement: String, Sendable, Codable, CaseIterable {
    case barbell, dumbbell
}

public enum ScoreSex: String, Sendable, Codable, CaseIterable {
    case male, female, unspecified
}

/// One set the user reports. Weights are always kilograms (see CLAUDE.md).
public struct LiftSet: Sendable, Equatable, Codable {
    public var lift: BasicLift
    public var implement: LiftImplement
    public var weightKg: Double
    public var reps: Int

    public init(lift: BasicLift, implement: LiftImplement, weightKg: Double, reps: Int) {
        self.lift = lift
        self.implement = implement
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// The person being scored.
public struct AthleteProfile: Sendable, Equatable {
    public var sex: ScoreSex
    public var bodyweightKg: Double
    public var ageYears: Int

    public init(sex: ScoreSex, bodyweightKg: Double, ageYears: Int) {
        self.sex = sex
        self.bodyweightKg = bodyweightKg
        self.ageYears = ageYears
    }
}

/// Result for one lift.
public struct ScoreEstimate: Sendable, Equatable {
    public var lift: BasicLift
    /// 0...100.
    public var score: Double
    /// Estimated one-rep max in the logged unit (one dumbbell for dumbbell sets), kilograms.
    public var oneRepMaxKg: Double
    /// True while the score comes from a stand-in engine rather than the trained model.
    public var isPlaceholder: Bool

    public init(lift: BasicLift, score: Double, oneRepMaxKg: Double, isPlaceholder: Bool) {
        self.lift = lift
        self.score = score
        self.oneRepMaxKg = oneRepMaxKg
        self.isPlaceholder = isPlaceholder
    }
}

/// Scores a reported set. `ModelScoreEngine` is the trained model; callers must not depend on a concrete engine.
public protocol ScoreEngine: Sendable {
    /// `nil` for unusable input (non-positive weight or bodyweight, fewer than one rep).
    func estimate(_ set: LiftSet, for athlete: AthleteProfile) -> ScoreEstimate?
}

extension BasicLift {
    /// Scored catalog exercise for an onboarding lift. Dumbbell sets log ONE dumbbell (`per_hand`), matching the
    /// exercise's anchor ratio unit.
    public func scoringExerciseId(implement: LiftImplement) -> String {
        switch (self, implement) {
        case (.benchPress, .barbell): "barbell-bench-press-medium-grip"
        case (.benchPress, .dumbbell): "dumbbell-bench-press"
        case (.squat, .barbell): "barbell-full-squat"
        case (.squat, .dumbbell): "dumbbell-squat"
        case (.deadlift, .barbell): "barbell-deadlift"
        case (.deadlift, .dumbbell): "stiff-legged-dumbbell-deadlift"
        case (.overheadPress, .barbell): "barbell-shoulder-press"
        case (.overheadPress, .dumbbell): "dumbbell-shoulder-press"
        }
    }
}

/// The real score engine (P062): one set → current strength → exercise score against the default population.
public struct ModelScoreEngine: ScoreEngine {
    public let model: StrengthModel?

    public init(model: StrengthModel?) {
        self.model = model
    }

    /// Engine backed by the embedded base bundle.
    public init() {
        self.init(model: try? EmbeddedModelBundle.model())
    }

    public func estimate(_ set: LiftSet, for athlete: AthleteProfile) -> ScoreEstimate? {
        guard let model, athlete.ageYears > 0 else { return nil }
        let sex: ModelSex? = switch athlete.sex {
        case .male: .male
        case .female: .female
        case .unspecified: nil
        }
        let user = ScoringUser(sex: sex, age: Double(athlete.ageYears), bodyweightKg: athlete.bodyweightKg)
        let id = set.lift.scoringExerciseId(implement: set.implement)
        let logged = ScoringSet(day: 0, weightKg: set.weightKg, reps: set.reps)
        guard let strength = try? model.currentStrength(exerciseId: id, sets: [logged], user: user, asOfDay: 0),
              let e1rm = strength.e1rmKg,
              let result = try? model.exerciseScore(exerciseId: id, strength: strength, user: user) else { return nil }
        return ScoreEstimate(lift: set.lift, score: result.score, oneRepMaxKg: e1rm, isPlaceholder: false)
    }
}
