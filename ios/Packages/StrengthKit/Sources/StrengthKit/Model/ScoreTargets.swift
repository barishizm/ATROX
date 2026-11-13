// swiftlint:disable identifier_name
import Foundation

/// What it takes to reach a score threshold (P065): the inverse of `exerciseScore`.
public struct ScoreTarget: Sendable, Equatable {
    public var level: String
    public var minScore: Double
    /// e1RM (in the exercise's logged unit) at which the score reaches `minScore`.
    public var e1rmKg: Double
    /// Missing e1RM from the current value, never negative.
    public var gapKg: Double
}

/// Density of the reference population over the e1RM axis, for the "you are here" chart.
public struct ScoreDistribution: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var e1rmKg: Double
        /// Probability density per kg (integrates to ~1 over the plotted range).
        public var density: Double
    }

    public struct Marker: Sendable, Equatable {
        public var key: String
        public var e1rmKg: Double
    }

    public var points: [Point]
    public var median: Double
    /// One marker per level threshold, ascending.
    public var levels: [Marker]
}

extension StrengthModel {
    private static let probe = CurrentStrength(e1rmKg: nil, confidence: .high, stale: false, sessionsInWindow: 3)

    /// Unclipped z of an e1RM (the reported score clips to 1–99, which would flatten the search near the ends).
    func z(forE1RM e1rmKg: Double, exercise ex: TaxonomyExercise, user: ScoringUser, population: ReferencePopulation) throws(StrengthModelError)
        -> Double? {
        var strength = Self.probe
        strength.e1rmKg = e1rmKg
        return try exerciseScore(ex, strength: strength, user: user, population: population)?.z
    }

    /// Smallest e1RM whose z reaches `z` (monotone search in log space); nil when the exercise is not scorable by weight.
    func e1rm(forZ target: Double, exercise ex: TaxonomyExercise, user: ScoringUser, population: ReferencePopulation)
        throws(StrengthModelError) -> Double? {
        guard ex.scorable, ex.scoringType == "weighted" || ex.scoringType == "bodyweight_loaded" else { return nil }
        guard let start = try z(forE1RM: 50, exercise: ex, user: user, population: population) else { return nil }
        var lo = 50.0, hi = 50.0
        if start < target {
            for _ in 0..<40 {
                hi *= 1.5
                guard let value = try z(forE1RM: hi, exercise: ex, user: user, population: population) else { return nil }
                if value >= target { break }
                lo = hi
            }
        } else {
            for _ in 0..<40 {
                lo /= 1.5
                guard let value = try z(forE1RM: lo, exercise: ex, user: user, population: population) else { return nil }
                if value < target { break }
                hi = lo
            }
        }
        for _ in 0..<60 {
            let mid = (lo * hi).squareRoot()
            guard let value = try z(forE1RM: mid, exercise: ex, user: user, population: population) else { return nil }
            if value < target { lo = mid } else { hi = mid }
        }
        return hi
    }

    /// e1RM that scores `targetScore` (0–100 percentile) for this user.
    public func e1rmForScore(exerciseId: String, targetScore: Double, user: ScoringUser, population: ReferencePopulation? = nil)
        throws(StrengthModelError) -> Double? {
        let ex = try exercise(exerciseId)
        let user = try user.validated()
        let p = min(max(targetScore / 100, 1e-9), 1 - 1e-9)
        return try e1rm(forZ: SpecialFunctions.normalQuantile(p), exercise: ex, user: user, population: population ?? params.exerciseScore.defaultPopulation)
    }

    /// The first level above the current score, with the e1RM it needs. nil at the top level or when not computable.
    public func nextLevelTarget(
        exerciseId: String, currentScore: Double, currentE1RMKg: Double, user: ScoringUser, population: ReferencePopulation? = nil
    ) throws(StrengthModelError) -> ScoreTarget? {
        guard let next = params.levels.first(where: { $0.min > currentScore }) else { return nil }
        guard let needed = try e1rmForScore(exerciseId: exerciseId, targetScore: next.min, user: user, population: population) else {
            return nil
        }
        return ScoreTarget(level: next.key, minScore: next.min, e1rmKg: needed, gapKg: max(0, needed - currentE1RMKg))
    }

    /// Weight to type for a set of `reps` that produces `e1rmKg`, in the exercise's logged convention (added load for
    /// bodyweight moves; nil when the bodyweight share alone already exceeds it).
    public func loadForReps(exerciseId: String, e1rmKg: Double, reps: Int, user: ScoringUser) throws(StrengthModelError) -> Double? {
        let ex = try exercise(exerciseId)
        let fraction = e1rm.curve(for: ex.movementPattern).fraction(Double(max(reps, 1)), rMax: e1rm.params.rMax)
        let effective = e1rmKg * fraction
        if ex.scoringType == "bodyweight_loaded" {
            guard let share = ex.bwFraction else { throw .missingParameter("\(ex.id): bw_fraction") }
            let added = effective - share * user.bodyweightKg
            return added > 0 ? added : nil
        }
        return effective
    }

    /// Population density over e1RM between the 0.5th and 99.5th percentile, with the median and level thresholds.
    public func scoreDistribution(
        exerciseId: String, user: ScoringUser, population: ReferencePopulation? = nil, pointCount: Int = 60
    ) throws(StrengthModelError) -> ScoreDistribution? {
        let ex = try exercise(exerciseId)
        let user = try user.validated()
        let pop = population ?? params.exerciseScore.defaultPopulation
        let zEdge = 2.6
        guard let low = try e1rm(forZ: -zEdge, exercise: ex, user: user, population: pop),
              let high = try e1rm(forZ: zEdge, exercise: ex, user: user, population: pop),
              let median = try e1rm(forZ: 0, exercise: ex, user: user, population: pop), high > low, pointCount >= 3 else { return nil }
        let step = (high - low) / Double(pointCount - 1)
        var cdf: [Double] = []
        for index in 0..<(pointCount + 2) {
            let e = max(1e-6, low + step * Double(index - 1))
            guard let value = try z(forE1RM: e, exercise: ex, user: user, population: pop) else { return nil }
            cdf.append(SpecialFunctions.normalCDF(value))
        }
        let points = (0..<pointCount).map { index in
            ScoreDistribution.Point(e1rmKg: low + step * Double(index), density: max(0, (cdf[index + 2] - cdf[index]) / (2 * step)))
        }
        var markers: [ScoreDistribution.Marker] = []
        for level in params.levels where level.min > 0 {
            if let e = try e1rmForScore(exerciseId: exerciseId, targetScore: level.min, user: user, population: pop) {
                markers.append(.init(key: level.key, e1rmKg: e))
            }
        }
        return ScoreDistribution(points: points, median: median, levels: markers)
    }
}
