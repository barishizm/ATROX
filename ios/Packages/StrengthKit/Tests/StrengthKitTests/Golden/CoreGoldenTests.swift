import Foundation
@testable import StrengthKit
import Testing

/// P061: numeric core against `ml/golden` (e1rm, anchor, calibration, current strength, exercise score).
@Suite struct CoreGoldenTests {
    private let model = Golden.model

    struct E1RMCase: Decodable {
        struct Input: Decodable { let pattern: String?, weightKg: Double, reps: Int, rir: Double?, isWarmup: Bool }
        struct Expected: Decodable { let e1rmKg: Double, confidence: Double }
        let input: Input
        let expected: Expected
    }

    @Test func e1rm() throws {
        for (idx, c) in try Golden.load("e1rm", as: E1RMCase.self).enumerated() {
            let ex = TaxonomyExercise(id: "x", movementPattern: c.input.pattern, scoringType: "weighted")
            let set = ScoringSet(day: 0, weightKg: c.input.weightKg, reps: c.input.reps, rir: c.input.rir, isWarmup: c.input.isWarmup)
            let est = try model.scoreSet(ex, set, user: ScoringUser(sex: .male, age: 30, bodyweightKg: 80))
            #expect(Golden.close(est.valueKg, c.expected.e1rmKg), "case \(idx): e1rm \(est.valueKg) vs \(c.expected.e1rmKg)")
            #expect(Golden.close(est.confidence, c.expected.confidence), "case \(idx): confidence")
        }
    }

    struct AnchorCase: Decodable {
        struct Input: Decodable { let lift: AnchorLift, sex: ModelSex, age: Double, bodyweightKg: Double, valueKg: Double }
        struct Expected: Decodable { let z: Double, scale: Double }
        let input: Input
        let expected: Expected
    }

    @Test func anchor() throws {
        for (idx, c) in try Golden.load("anchor", as: AnchorCase.self).enumerated() {
            let res = try model.competitorZ(
                lift: c.input.lift, sex: c.input.sex, age: c.input.age, bodyweightKg: c.input.bodyweightKg, valueKg: c.input.valueKg
            )
            #expect(Golden.close(res.z, c.expected.z), "case \(idx): z \(res.z) vs \(c.expected.z)")
            #expect(Golden.close(res.scale, c.expected.scale), "case \(idx): scale \(res.scale) vs \(c.expected.scale)")
        }
    }

    struct CalibrationCase: Decodable {
        struct Input: Decodable {
            let zC: Double, sC: Double, population: ReferencePopulation, sex: ModelSex, lift: AnchorLift, age: Double
        }
        struct Expected: Decodable { let zG: Double, sG: Double }
        let input: Input
        let expected: Expected
    }

    @Test func calibration() throws {
        for (idx, c) in try Golden.load("calibration", as: CalibrationCase.self).enumerated() {
            let i = c.input
            let res = try model.calibrate(zC: i.zC, sC: i.sC, population: i.population, sex: i.sex, lift: i.lift, age: i.age)
            #expect(Golden.close(res.z, c.expected.zG), "case \(idx): z")
            #expect(Golden.close(res.scale, c.expected.sG), "case \(idx): scale")
        }
    }

    struct StrengthCase: Decodable {
        struct Input: Decodable { let exerciseId: String, user: Golden.User, asOfDay: Int, sets: [Golden.LoggedSet] }
        struct Expected: Decodable {
            let e1rmKg: Double?, confidence: ScoreConfidence, stale: Bool, sessionsInWindow: Int, flaggedDays: [Int]
        }
        let input: Input
        let expected: Expected
    }

    @Test func currentStrength() throws {
        for (idx, c) in try Golden.load("current_strength", as: StrengthCase.self).enumerated() {
            let res = try model.currentStrength(
                exerciseId: c.input.exerciseId, sets: c.input.sets.map(\.scoring), user: c.input.user.scoring, asOfDay: c.input.asOfDay
            )
            #expect(Golden.close(res.e1rmKg, c.expected.e1rmKg), "case \(idx): e1rm \(String(describing: res.e1rmKg))")
            #expect(res.confidence == c.expected.confidence, "case \(idx): confidence")
            #expect(res.stale == c.expected.stale, "case \(idx): stale")
            #expect(res.sessionsInWindow == c.expected.sessionsInWindow, "case \(idx): sessions")
            #expect(res.flaggedDays == c.expected.flaggedDays, "case \(idx): flagged")
        }
    }

    struct ScoreCase: Decodable {
        struct Strength: Decodable { let e1rmKg: Double, confidence: ScoreConfidence, stale: Bool }
        struct Input: Decodable {
            let exerciseId: String, user: Golden.User, strength: Strength, population: ReferencePopulation, reps: Double?
        }
        let input: Input
        let expected: Golden.Score?
    }

    @Test func exerciseScore() throws {
        for (idx, c) in try Golden.load("exercise_score", as: ScoreCase.self).enumerated() {
            let s = c.input.strength
            let res = try model.exerciseScore(
                exerciseId: c.input.exerciseId,
                strength: CurrentStrength(e1rmKg: s.e1rmKg, confidence: s.confidence, stale: s.stale, sessionsInWindow: 3),
                user: c.input.user.scoring, population: c.input.population, reps: c.input.reps
            )
            Golden.check(res, c.expected, "case \(idx) \(c.input.exerciseId)")
        }
    }
}

@Suite struct NumericCoreTests {
    @Test func normalQuantileInvertsCDF() {
        for prob in [1e-12, 1e-6, 0.01, 0.0249, 0.3, 0.5, 0.8, 0.976, 0.999999] {
            let x = SpecialFunctions.normalQuantile(prob)
            #expect(abs(SpecialFunctions.normalCDF(x) - prob) <= 1e-14 + prob * 1e-12)
        }
        #expect(SpecialFunctions.normalQuantile(0) == -.infinity)
        #expect(SpecialFunctions.normalQuantile(1.5).isNaN)
    }

    @Test func gammaInverseRoundTrips() {
        for a in [0.05, 0.3, 0.55, 1, 2] {
            for prob in [1e-8, 0.01, 0.2, 0.5, 0.9, 0.999999] {
                let x = SpecialFunctions.inverseRegularizedGammaP(a, prob)
                #expect(abs(SpecialFunctions.regularizedGammaP(a, x) - prob) < 1e-12, "a=\(a) p=\(prob)")
            }
        }
    }

    @Test func boxCoxQuantileInvertsCDF() {
        for family in [BoxCoxDistribution.Family.bccg, .bcpe] {
            for nu in [-1.0, 0, 0.6] {
                let dist = BoxCoxDistribution(family: family, mu: 100, sigma: 0.2, nu: nu, tau: 1.8)
                for prob in [0.01, 0.16, 0.5, 0.84, 0.99] {
                    #expect(abs(dist.cdf(dist.quantile(prob)) - prob) < 1e-10, "\(family) nu=\(nu) p=\(prob)")
                }
            }
        }
    }

    @Test func invalidInputThrowsInsteadOfCrashing() throws {
        let model = Golden.model
        let strength = CurrentStrength(e1rmKg: 100, confidence: .high, stale: false, sessionsInWindow: 4)
        #expect(throws: StrengthModelError.self) {
            try model.exerciseScore(
                exerciseId: "barbell-full-squat", strength: strength, user: ScoringUser(sex: .male, age: .nan, bodyweightKg: 80)
            )
        }
        #expect(throws: StrengthModelError.self) {
            try model.exerciseScore(exerciseId: "no-such-exercise", strength: strength, user: ScoringUser(sex: nil, age: 30, bodyweightKg: 80))
        }
        #expect(throws: StrengthModelError.unsupportedSchema(found: 99, supported: 1)) {
            _ = try ModelParams.decode(Data(#"{"schemaVersion":99}"#.utf8))
        }
    }
}
