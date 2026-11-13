// swiftlint:disable identifier_name
import Foundation
import Testing

@testable import StrengthKit

@Suite("Score targets (inverse score)")
struct ScoreTargetsTests {
    let model: StrengthModel = { do { return try EmbeddedModelBundle.model() } catch { fatalError("\(error)") } }()
    let man = ScoringUser(sex: .male, age: 28, bodyweightKg: 82)
    let bench = "barbell-bench-press-medium-grip"

    private func score(_ e1rm: Double, _ user: ScoringUser, population: ReferencePopulation) throws -> ExerciseScore {
        let strength = CurrentStrength(e1rmKg: e1rm, confidence: .high, stale: false, sessionsInWindow: 3)
        return try #require(try model.exerciseScore(exerciseId: bench, strength: strength, user: user, population: population))
    }

    @Test("target e1RM hits the requested percentile in every population", arguments: ReferencePopulation.allCases)
    func inverseMatchesForward(population: ReferencePopulation) throws {
        // Below ~15 the general population saturates at the anchor's CDF clip, so tiny targets are not invertible.
        for target in [25.0, 35, 50, 73, 90] {
            let e1rm = try #require(try model.e1rmForScore(exerciseId: bench, targetScore: target, user: man, population: population))
            let got = try score(e1rm, man, population: population).score
            #expect(abs(got - target) < 0.05, "target \(target) → \(got)")
        }
    }

    @Test("the unspecified-sex mixture inverts too")
    func mixtureInverts() throws {
        let user = ScoringUser(sex: nil, age: 40, bodyweightKg: 70)
        let e1rm = try #require(try model.e1rmForScore(exerciseId: bench, targetScore: 60, user: user))
        #expect(abs(try score(e1rm, user, population: .gym).score - 60) < 0.05)
    }

    @Test("next level target: the load for the suggested reps really crosses the threshold")
    func nextLevelLoadCrossesThreshold() throws {
        let current = try score(70, man, population: .gym)
        let target = try #require(try model.nextLevelTarget(exerciseId: bench, currentScore: current.score, currentE1RMKg: 70, user: man))
        #expect(target.minScore > current.score)
        #expect(target.gapKg > 0)
        for reps in [1, 3, 5, 8] {
            let load = try #require(try model.loadForReps(exerciseId: bench, e1rmKg: target.e1rmKg, reps: reps, user: man))
            // Round up to the next 0.5 kg step like a real plate: still must cross.
            let typed = (load / 0.5).rounded(.up) * 0.5
            let sets = [ScoringSet(day: 0, weightKg: typed, reps: reps)]
            let strength = try model.currentStrength(exerciseId: bench, sets: sets, user: man, asOfDay: 0)
            let result = try #require(try model.exerciseScore(exerciseId: bench, strength: strength, user: man))
            #expect(result.score >= target.minScore - 1e-6, "\(reps) reps at \(typed) kg → \(result.score) < \(target.minScore)")
        }
    }

    @Test("top level has no next target")
    func topLevel() throws {
        #expect(try model.nextLevelTarget(exerciseId: bench, currentScore: 99, currentE1RMKg: 300, user: man) == nil)
    }

    @Test("bodyweight-loaded exercises return added load, nil when bodyweight covers it")
    func bodyweightLoaded() throws {
        let id = try #require(model.exercises.values.first { $0.scoringType == "bodyweight_loaded" }?.id)
        let ex = try model.exercise(id)
        let share = try #require(ex.bwFraction) * man.bodyweightKg
        let added = try model.loadForReps(exerciseId: id, e1rmKg: share + 40, reps: 1, user: man)
        #expect(added != nil && added! > 0)
        #expect(try model.loadForReps(exerciseId: id, e1rmKg: share * 0.5, reps: 1, user: man) == nil)
    }

    @Test("distribution: density integrates to the CDF mass, median sits at score 50, levels ascend")
    func distribution() throws {
        let dist = try #require(try model.scoreDistribution(exerciseId: bench, user: man))
        let area = zip(dist.points, dist.points.dropFirst()).reduce(0.0) { $0 + ($1.0.density + $1.1.density) / 2 * ($1.1.e1rmKg - $1.0.e1rmKg) }
        let ex = try model.exercise(bench)
        let pop = model.params.exerciseScore.defaultPopulation
        let zLow = try #require(try model.z(forE1RM: dist.points.first!.e1rmKg, exercise: ex, user: man, population: pop))
        let zHigh = try #require(try model.z(forE1RM: dist.points.last!.e1rmKg, exercise: ex, user: man, population: pop))
        let mass = SpecialFunctions.normalCDF(zHigh) - SpecialFunctions.normalCDF(zLow)
        #expect(abs(area - mass) < 0.01, "area \(area) vs mass \(mass)")
        #expect(abs(try score(dist.median, man, population: .gym).score - 50) < 0.05)
        #expect(dist.levels.map(\.e1rmKg) == dist.levels.map(\.e1rmKg).sorted())
        #expect(dist.points.allSatisfy { $0.density >= 0 })
    }

    @Test("unscorable or time exercises give no target")
    func unscorable() throws {
        #expect(try model.e1rmForScore(exerciseId: bench, targetScore: 50, user: ScoringUser(sex: .male, age: 28, bodyweightKg: 82)) != nil)
        #expect(throws: StrengthModelError.self) { try model.e1rmForScore(exerciseId: "nope", targetScore: 50, user: man) }
    }
}
