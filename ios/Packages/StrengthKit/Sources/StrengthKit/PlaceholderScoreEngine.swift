import Foundation

/// TEMPORARY stand-in for the trained model (P021). Bodyweight-ratio heuristic only: it ignores age and the
/// reference population and is NOT calibrated. Replaced by the real engine in P061–P062; delete this file then.
public struct PlaceholderScoreEngine: ScoreEngine {
    /// Reps above this are treated as this many: Epley is unreliable for long sets.
    static let repCap = 12
    /// A pair of dumbbells moves about this share of the barbell load for the same lift.
    static let dumbbellFactor = 0.85
    /// Women's standards relative to men's; `unspecified` takes the middle.
    static let femaleFactor = 0.6
    static let unspecifiedFactor = 0.8

    public init() {}

    /// Bodyweight multiple (men) that maps to a score of 100.
    static func referenceRatio(for lift: BasicLift) -> Double {
        switch lift {
        case .benchPress: 2.0
        case .squat: 2.5
        case .deadlift: 3.0
        case .overheadPress: 1.25
        }
    }

    static func sexFactor(_ sex: ScoreSex) -> Double {
        switch sex {
        case .male: 1
        case .female: femaleFactor
        case .unspecified: unspecifiedFactor
        }
    }

    public func estimate(_ set: LiftSet, for athlete: AthleteProfile) -> ScoreEstimate? {
        guard set.weightKg.isFinite, athlete.bodyweightKg.isFinite, athlete.bodyweightKg > 0,
              let oneRepMax = E1RMModel.standard.estimate(weightKg: set.weightKg, reps: Swift.min(set.reps, Self.repCap))?.valueKg
        else { return nil }
        let barbellEquivalent: Double
        switch set.implement {
        case .barbell: barbellEquivalent = oneRepMax
        case .dumbbell: barbellEquivalent = oneRepMax * 2 / Self.dumbbellFactor
        }
        let ratio = barbellEquivalent / athlete.bodyweightKg
        let reference = Self.referenceRatio(for: set.lift) * Self.sexFactor(athlete.sex)
        let score = Swift.min(Swift.max(100 * ratio / reference, 0), 100)
        return ScoreEstimate(lift: set.lift, score: score, oneRepMaxKg: barbellEquivalent, isPlaceholder: true)
    }
}
