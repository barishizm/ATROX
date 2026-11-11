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
    /// Estimated barbell-equivalent one-rep max in kilograms.
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

/// Scores a reported set. The real model (P061–P062) is plugged in behind this protocol;
/// callers must not depend on a concrete engine.
public protocol ScoreEngine: Sendable {
    /// `nil` for unusable input (non-positive weight or bodyweight, fewer than one rep).
    func estimate(_ set: LiftSet, for athlete: AthleteProfile) -> ScoreEstimate?
}
