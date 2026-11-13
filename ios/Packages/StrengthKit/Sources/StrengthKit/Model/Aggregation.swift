import Foundation

/// Muscle-group or overall score (docs/03-ML-MODEL.md §8), from `gymml.scoring.GroupScore`.
public struct GroupScore: Sendable, Equatable {
    public var key: String
    public var score: Double
    public var z: Double
    /// Number of exercise scores that went in.
    public var count: Int
    public var confidence: ScoreConfidence
    /// Overall only: too few patterns or no upper + lower body coverage yet.
    public var provisional: Bool
    public var level: String
    /// Overall only: covered movement patterns in parameter order.
    public var patterns: [String]
}

extension StrengthModel {
    /// §8: z = Σ w z / sqrt(wᵀ R w) with a unit diagonal.
    static func combine(_ zs: [Double], weights: [Double], correlation: (Int, Int) -> Double) -> Double {
        var num = 0.0, den = 0.0
        for i in zs.indices {
            num += weights[i] * zs[i]
            for j in zs.indices {
                den += weights[i] * weights[j] * (i == j ? 1 : correlation(i, j))
            }
        }
        return num / den.squareRoot()
    }

    func pairCorrelation(_ lhs: ExerciseScore, _ rhs: ExerciseScore) -> Double {
        let cfg = params.aggregate
        guard let la = lhs.anchor, let ra = rhs.anchor else { return cfg.unknownPairCorrelation }
        if la == ra { return cfg.sameAnchorCorrelation }
        let vars = params.correlation.variables
        guard let li = vars.firstIndex(of: la.rawValue), let ri = vars.firstIndex(of: ra.rawValue) else {
            return cfg.unknownPairCorrelation
        }
        return params.correlation.matrix[li][ri]
    }

    func itemWeight(_ score: ExerciseScore) -> Double {
        let cfg = params.aggregate
        var weight = cfg.confidenceWeights[score.confidence.rawValue] ?? 0
        if score.stale { weight *= cfg.staleWeight }
        if score.isMachine { weight *= cfg.machineWeight }
        return weight
    }

    private func combineScores(_ items: [ExerciseScore], extraWeights: [Double]) -> Double {
        let weights = zip(items, extraWeights).map { itemWeight($0) * $1 }
        return Self.combine(items.map(\.z), weights: weights) { pairCorrelation(items[$0], items[$1]) }
    }

    private func toScore(_ zv: Double) -> Double { clipScore(100 * SpecialFunctions.normalCDF(zv)) }

    /// Primary muscles weigh 1.0, secondary 0.4 (a muscle listed as both counts as primary).
    public func muscleGroupScores(_ scores: [ExerciseScore]) throws(StrengthModelError) -> [String: GroupScore] {
        let weights = params.aggregate.muscleWeights
        var groups: [String: [(ExerciseScore, Double)]] = [:]
        for score in scores {
            let ex = try exercise(score.exerciseId)
            for muscle in ex.primaryMuscles { groups[muscle, default: []].append((score, weights.primary)) }
            for muscle in ex.secondaryMuscles where !ex.primaryMuscles.contains(muscle) {
                groups[muscle, default: []].append((score, weights.secondary))
            }
        }
        var out: [String: GroupScore] = [:]
        for (muscle, items) in groups {
            let zv = combineScores(items.map(\.0), extraWeights: items.map(\.1))
            let score = toScore(zv)
            out[muscle] = GroupScore(
                key: muscle, score: score, z: zv, count: items.count, confidence: items.map(\.0.confidence).max() ?? .low,
                provisional: false, level: levelKey(score: score), patterns: []
            )
        }
        return out
    }

    /// Overall score over movement patterns (pattern correlation 0.6); provisional below the coverage rules.
    public func overallScore(_ scores: [ExerciseScore]) throws(StrengthModelError) -> GroupScore? {
        let cfg = params.aggregate
        var byPattern: [String: [ExerciseScore]] = [:]
        for score in scores {
            if let pattern = try exercise(score.exerciseId).movementPattern, cfg.patterns.contains(pattern) {
                byPattern[pattern, default: []].append(score)
            }
        }
        guard !byPattern.isEmpty else { return nil }
        let patterns = cfg.patterns.filter { byPattern[$0] != nil }
        let groups = patterns.compactMap { byPattern[$0] }
        let zs = groups.map { combineScores($0, extraWeights: Array(repeating: 1, count: $0.count)) }
        let weights = groups.map { $0.map(itemWeight).max() ?? 0 }
        let zv = Self.combine(zs, weights: weights) { _, _ in cfg.patternCorrelation }
        let score = toScore(zv)
        let hasUpper = patterns.contains(where: cfg.upperPatterns.contains)
        let hasLower = patterns.contains(where: cfg.lowerPatterns.contains)
        return GroupScore(
            key: "overall", score: score, z: zv, count: scores.count, confidence: scores.map(\.confidence).max() ?? .low,
            provisional: patterns.count < cfg.minPatternsForFullScore || !(hasUpper && hasLower),
            level: levelKey(score: score), patterns: patterns
        )
    }
}
