import Foundation

/// The person being scored. `sex == nil` scores a 50/50 mixture (docs/03-ML-MODEL.md §4.5).
public struct ScoringUser: Sendable, Equatable {
    public var sex: ModelSex?
    public var age: Double
    public var bodyweightKg: Double

    public init(sex: ModelSex?, age: Double, bodyweightKg: Double) {
        self.sex = sex
        self.age = age
        self.bodyweightKg = bodyweightKg
    }

    func validated() throws(StrengthModelError) -> ScoringUser {
        guard age.isFinite, age > 0, bodyweightKg.isFinite, bodyweightKg > 0 else {
            throw .invalidInput("age and bodyweight must be finite and positive")
        }
        return self
    }
}

/// One logged set. `day` is a day number (any fixed origin; only differences matter). `weightKg` is the number the
/// user typed, in the exercise's load convention (per hand, per side, total, or added load for bodyweight moves).
public struct ScoringSet: Sendable, Equatable {
    public var day: Int
    public var weightKg: Double
    public var reps: Int
    public var rir: Double?
    public var isWarmup: Bool
    /// The user answered "yes" to "Did you enter this set correctly?".
    public var confirmed: Bool

    public init(day: Int, weightKg: Double, reps: Int, rir: Double? = nil, isWarmup: Bool = false, confirmed: Bool = false) {
        self.day = day
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
        self.confirmed = confirmed
    }
}

/// Score model: parameters, taxonomy and the anchor distribution of one model bundle. Mirrors `gymml.scoring`.
public struct StrengthModel: Sendable {
    public let params: ModelParams
    public let exercises: [String: TaxonomyExercise]
    public let anchor: any AnchorDistribution
    public let e1rm: E1RMModel

    public init(params: ModelParams, taxonomy: ModelTaxonomy, anchor: any AnchorDistribution) {
        self.params = params
        self.exercises = Dictionary(taxonomy.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.anchor = anchor
        self.e1rm = E1RMModel(params: params.e1rm)
    }

    public func exercise(_ id: String) throws(StrengthModelError) -> TaxonomyExercise {
        guard let ex = exercises[id] else { throw .invalidInput("unknown or unscorable exercise \(id)") }
        return ex
    }

    // MARK: Set → e1RM

    /// Load the curve sees: bodyweight share + added load for `bodyweight_loaded`, the typed number otherwise.
    public func effectiveLoad(_ ex: TaxonomyExercise, weightKg: Double, user: ScoringUser) throws(StrengthModelError) -> Double {
        guard ex.scoringType == "bodyweight_loaded" else { return weightKg }
        guard let fraction = ex.bwFraction else { throw .missingParameter("\(ex.id): bw_fraction") }
        return fraction * user.bodyweightKg + weightKg
    }

    public func scoreSet(_ ex: TaxonomyExercise, _ set: ScoringSet, user: ScoringUser) throws(StrengthModelError) -> E1RMEstimate {
        let load = try effectiveLoad(ex, weightKg: set.weightKg, user: user)
        return e1rm.score(loadKg: load, reps: set.reps, rir: set.rir, isWarmup: set.isWarmup, pattern: ex.movementPattern)
    }

    // MARK: Levels

    public func levelKey(score: Double) -> String {
        var key = params.levels.first?.key ?? ""
        for level in params.levels where score >= level.min { key = level.key }
        return key
    }

    func clipScore(_ value: Double) -> Double {
        min(max(value, params.exerciseScore.scoreClip[0]), params.exerciseScore.scoreClip[1])
    }

    /// Sexes and weights to score: the user's own, or the unspecified-sex mixture (M then F).
    func sexMix(_ user: ScoringUser) throws(StrengthModelError) -> [(ModelSex, Double)] {
        if let sex = user.sex { return [(sex, 1)] }
        let mix = params.exerciseScore.unspecifiedSexMix
        guard let male = mix["M"], let female = mix["F"] else { throw .missingParameter("unspecifiedSexMix") }
        return [(.male, male), (.female, female)]
    }
}
