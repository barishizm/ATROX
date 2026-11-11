import Testing

@testable import StrengthKit

struct PlaceholderScoreEngineTests {
    private let engine = PlaceholderScoreEngine()
    private let man = AthleteProfile(sex: .male, bodyweightKg: 80, ageYears: 30)

    private func set(_ lift: BasicLift = .benchPress, _ implement: LiftImplement = .barbell, kg: Double, reps: Int) -> LiftSet {
        LiftSet(lift: lift, implement: implement, weightKg: kg, reps: reps)
    }

    @Test func isMarkedAsPlaceholder() throws {
        let result = try #require(engine.estimate(set(kg: 80, reps: 1), for: man))
        #expect(result.isPlaceholder)
    }

    @Test func singleRepBodyweightBenchScoresHalf() throws {
        // 1.0 x bodyweight against a 2.0 reference.
        let result = try #require(engine.estimate(set(kg: 80, reps: 1), for: man))
        #expect(abs(result.score - 50) < 1e-9)
        #expect(result.lift == .benchPress)
        #expect(result.oneRepMaxKg == 80)
    }

    @Test func moreWeightOrMoreRepsScoreHigher() throws {
        let base = try #require(engine.estimate(set(kg: 60, reps: 5), for: man)).score
        let heavier = try #require(engine.estimate(set(kg: 70, reps: 5), for: man)).score
        let longer = try #require(engine.estimate(set(kg: 60, reps: 8), for: man)).score
        #expect(heavier > base)
        #expect(longer > base)
    }

    @Test func scoreIsCappedAtHundred() throws {
        let result = try #require(engine.estimate(set(kg: 400, reps: 1), for: man))
        #expect(result.score == 100)
    }

    @Test func repsBeyondTheCapAddNothing() throws {
        let twelve = try #require(engine.estimate(set(kg: 50, reps: 12), for: man))
        let thirty = try #require(engine.estimate(set(kg: 50, reps: 30), for: man))
        #expect(twelve.score == thirty.score)
    }

    @Test func standardsDifferBySex() throws {
        let woman = AthleteProfile(sex: .female, bodyweightKg: 80, ageYears: 30)
        let other = AthleteProfile(sex: .unspecified, bodyweightKg: 80, ageYears: 30)
        let sample = set(kg: 60, reps: 5)
        let men = try #require(engine.estimate(sample, for: man)).score
        let women = try #require(engine.estimate(sample, for: woman)).score
        let unspecified = try #require(engine.estimate(sample, for: other)).score
        #expect(women > unspecified && unspecified > men)
    }

    @Test func lighterBodyweightScoresHigherForSameLoad() throws {
        let light = AthleteProfile(sex: .male, bodyweightKg: 65, ageYears: 30)
        let sample = set(kg: 80, reps: 5)
        #expect(try #require(engine.estimate(sample, for: light)).score > (try #require(engine.estimate(sample, for: man)).score))
    }

    @Test func eachLiftHasItsOwnReference() throws {
        let overhead = try #require(engine.estimate(set(.overheadPress, kg: 60, reps: 1), for: man)).score
        let squat = try #require(engine.estimate(set(.squat, kg: 60, reps: 1), for: man)).score
        #expect(overhead > squat)
    }

    @Test func dumbbellPairIsConvertedToBarbellEquivalent() throws {
        // 2 x 30 kg dumbbells ~ 60 / 0.85 kg on the bar for a single.
        let result = try #require(engine.estimate(set(.benchPress, .dumbbell, kg: 30, reps: 1), for: man))
        #expect(abs(result.oneRepMaxKg - 60 / 0.85) < 1e-9)
    }

    @Test func rejectsUnusableInput() {
        #expect(engine.estimate(set(kg: 0, reps: 5), for: man) == nil)
        #expect(engine.estimate(set(kg: -10, reps: 5), for: man) == nil)
        #expect(engine.estimate(set(kg: 60, reps: 0), for: man) == nil)
        #expect(engine.estimate(set(kg: .nan, reps: 5), for: man) == nil)
        #expect(engine.estimate(set(kg: 60, reps: 5), for: AthleteProfile(sex: .male, bodyweightKg: 0, ageYears: 30)) == nil)
    }
}
