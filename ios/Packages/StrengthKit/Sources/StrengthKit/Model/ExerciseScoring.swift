// swiftlint:disable identifier_name nesting
import Foundation

/// 1–99 score of one exercise with its ±1 band (docs/03-ML-MODEL.md §4–§6), from `gymml.scoring.exercise_score`.
public struct ExerciseScore: Sendable, Equatable {
    public var exerciseId: String
    public var score: Double
    public var z: Double
    public var bandLow: Double
    public var bandHigh: Double
    public var confidence: ScoreConfidence
    public var level: String
    public var population: ReferencePopulation
    public var isMachine: Bool
    public var anchor: AnchorLift?
    public var stale: Bool

    public init(
        exerciseId: String, score: Double, z: Double, bandLow: Double, bandHigh: Double, confidence: ScoreConfidence,
        level: String, population: ReferencePopulation, isMachine: Bool, anchor: AnchorLift?, stale: Bool = false
    ) {
        self.exerciseId = exerciseId
        self.score = score
        self.z = z
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.confidence = confidence
        self.level = level
        self.population = population
        self.isMachine = isMachine
        self.anchor = anchor
        self.stale = stale
    }
}

extension StrengthModel {
    // MARK: Anchor + calibration

    /// Competitor z = Φ⁻¹(F(y | x)) (clipped) and the log-scale spread s_c = (log Q84 − log Q16)/2.
    public func competitorZ(lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, valueKg: Double)
        throws(StrengthModelError) -> (z: Double, scale: Double) {
        let clip = params.anchor.cdfClip, quantiles = params.anchor.scaleQuantiles
        let cdf = try anchor.cdf(lift: lift, sex: sex, age: age, bodyweightKg: bodyweightKg, valueKg: valueKg)
        let low = try anchor.quantile(lift: lift, sex: sex, age: age, bodyweightKg: bodyweightKg, prob: quantiles[0])
        let high = try anchor.quantile(lift: lift, sex: sex, age: age, bodyweightKg: bodyweightKg, prob: quantiles[1])
        let zc = SpecialFunctions.normalQuantile(min(max(cdf, clip[0]), clip[1]))
        return (zc, (log(high) - log(low)) / 2)
    }

    /// §5.1: z_g = (z_c + δ/s_c)/κ and s_g = κ·s_c. Competitors keep z_c, s_c. Ages under the first calibration band use
    /// it; ages past 85 use the last band (the anchor model clips age at 85 as well).
    public func calibrate(zC: Double, sC: Double, population: ReferencePopulation, sex: ModelSex, lift: AnchorLift, age: Double)
        throws(StrengthModelError) -> (z: Double, scale: Double) {
        if population == .competitor { return (zC, sC) }
        let cal = params.calibration
        let clamped = min(max(age, params.exerciseScore.calibrationMinAge), 85)
        guard let band = cal.ageBands.first(where: { $0.min <= clamped && clamped < $0.max }) else {
            throw .invalidInput("age \(age) outside calibration bands")
        }
        guard let delta = cal.delta[population.rawValue]?[sex.rawValue]?[lift.rawValue]?[band.key],
              let kappa = cal.kappa[population.rawValue]?[sex.rawValue] else {
            throw .missingParameter("calibration \(population.rawValue)/\(sex.rawValue)/\(lift.rawValue)/\(band.key)")
        }
        return ((zC + delta / sC) / kappa, kappa * sC)
    }

    /// Medians' half width of the P055 uncertainty band, as z (0 for competitors).
    func calibrationBandZ(_ population: ReferencePopulation) throws(StrengthModelError) -> Double {
        if population == .competitor { return 0 }
        guard let halfWidth = params.calibration.uncertaintyHalfWidth[population.rawValue] else {
            throw .missingParameter("uncertainty band \(population.rawValue)")
        }
        return SpecialFunctions.normalQuantile(0.5 + halfWidth / 100)
    }

    // MARK: Exercise score

    public func isMachine(_ ex: TaxonomyExercise) -> Bool {
        let cfg = params.exerciseScore
        return ex.loadConvention.map(cfg.machineConventions.contains) == true || cfg.machineEquipment.contains(ex.equipment ?? "")
    }

    func confidenceCap(_ ex: TaxonomyExercise) -> ScoreConfidence {
        if isMachine(ex) { return .low }
        let caps = params.exerciseScore.gradeConfidenceCap
        return (ex.isAnchor ? caps["anchor"] : caps[ex.ratioConfidence ?? "C"]) ?? .low
    }

    /// Shrunk population z of one sex and the ratio uncertainty after shrinkage (z units).
    private func anchorZ(_ ex: TaxonomyExercise, sex: ModelSex, user: ScoringUser, e1rmKg: Double, population: ReferencePopulation)
        throws(StrengthModelError) -> (z: Double, ratioBand: Double) {
        guard let lift = ex.anchor, let ratio = ex.ratio, ratio > 0 else { throw .missingParameter("\(ex.id): anchor/ratio") }
        guard let tau = ex.tau else { throw .missingParameter("\(ex.id): tau") }
        let comp = try competitorZ(lift: lift, sex: sex, age: user.age, bodyweightKg: user.bodyweightKg, valueKg: e1rmKg / ratio)
        let pop = try calibrate(zC: comp.z, sC: comp.scale, population: population, sex: sex, lift: lift, age: user.age)
        let norm = (pop.scale * pop.scale + tau * tau).squareRoot()
        return (pop.z * pop.scale / norm, tau / norm)
    }

    public func exerciseScore(
        exerciseId: String, strength: CurrentStrength, user: ScoringUser, population: ReferencePopulation? = nil, reps: Double? = nil
    ) throws(StrengthModelError) -> ExerciseScore? {
        try exerciseScore(exercise(exerciseId), strength: strength, user: user.validated(), population: population, reps: reps)
    }

    /// Score from current strength; `reps` (best set reps) is used for `reps_only` exercises. nil when not scorable.
    public func exerciseScore(
        _ ex: TaxonomyExercise, strength: CurrentStrength, user: ScoringUser, population: ReferencePopulation? = nil,
        reps: Double? = nil
    ) throws(StrengthModelError) -> ExerciseScore? {
        let pop = population ?? params.exerciseScore.defaultPopulation
        if ex.scoringType == "none" || ex.scoringType == "time" { return nil }
        if ex.scoringType == "reps_only" { return try repsOnlyScore(ex, user: user, reps: reps, population: pop) }
        guard ex.scorable, let e1rmKg = strength.e1rmKg else { return nil }
        guard e1rmKg.isFinite, e1rmKg > 0 else { throw .invalidInput("e1RM must be finite and positive") }
        let mix = try sexMix(user)
        let calB = try calibrationBandZ(pop)
        var parts: [(weight: Double, z: Double, band: Double)] = []
        for (sex, weight) in mix {
            let res = try anchorZ(ex, sex: sex, user: user, e1rmKg: e1rmKg, population: pop)
            parts.append((weight, res.z, (calB * calB + res.ratioBand * res.ratioBand).squareRoot()))
        }
        func pct(_ shift: Double) -> Double {
            parts.reduce(0) { $0 + $1.weight * SpecialFunctions.normalCDF($1.z + shift * $1.band) }
        }
        let mid = pct(0)
        let score = clipScore(100 * mid)
        return ExerciseScore(
            exerciseId: ex.id, score: score, z: SpecialFunctions.normalQuantile(min(max(mid, 1e-9), 1 - 1e-9)),
            bandLow: clipScore(100 * pct(-1)), bandHigh: clipScore(100 * pct(1)),
            confidence: min(strength.confidence, confidenceCap(ex)), level: levelKey(score: score), population: pop,
            isMachine: isMachine(ex), anchor: ex.anchor, stale: strength.stale
        )
    }

    private func repsOnlyScore(_ ex: TaxonomyExercise, user: ScoringUser, reps: Double?, population: ReferencePopulation)
        throws(StrengthModelError) -> ExerciseScore? {
        guard let reps else { return nil }
        var total = 0.0
        for (sex, weight) in try sexMix(user) {
            guard let value = repPercentile(exerciseId: ex.id, sex: sex, age: Int(user.age), reps: reps) else { return nil }
            total += weight * value
        }
        let score = clipScore(total)
        let clip = params.exerciseScore.scoreClip
        return ExerciseScore(
            exerciseId: ex.id, score: score, z: SpecialFunctions.normalQuantile(score / 100), bandLow: clip[0], bandHigh: clip[1],
            confidence: .low, level: levelKey(score: score), population: population, isMachine: false, anchor: nil
        )
    }

    /// Percentile from the age/sex rep norms: linear between points, clamped outside (`gymml.data.rep_norms`).
    func repPercentile(exerciseId: String, sex: ModelSex, age: Int, reps: Double) -> Double? {
        let curve = params.repNorms
            .filter { $0.exerciseIds.contains(exerciseId) && $0.sex == sex && $0.ageMin <= age && age <= $0.ageMax }
            .map { (reps: $0.reps, pct: $0.percentile) }
            .sorted { $0.pct < $1.pct }
        guard let first = curve.first, let last = curve.last else { return nil }
        if reps <= first.reps { return first.pct }
        if reps >= last.reps { return last.pct }
        for (lo, hi) in zip(curve, curve.dropFirst()) where lo.reps <= reps && reps <= hi.reps {
            return hi.reps == lo.reps ? lo.pct : lo.pct + (hi.pct - lo.pct) * (reps - lo.reps) / (hi.reps - lo.reps)
        }
        return nil
    }
}
