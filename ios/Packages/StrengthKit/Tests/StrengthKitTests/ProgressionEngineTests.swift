import Testing
@testable import StrengthKit

@Suite struct ProgressionEngineTests {
    private func sets(_ weight: Double, _ reps: [Int], rir: Int? = nil) -> [ProgressionSet] {
        reps.map { ProgressionSet(weightKg: weight, reps: $0, rir: rir) }
    }

    private func suggest(
        _ history: [[ProgressionSet]], range: ClosedRange<Int> = 8...12, targetRir: Int? = nil,
        loadClass: LoadClass = .upperCompound, step: Double = 2.5
    ) -> ProgressionSuggestion? {
        ProgressionEngine.suggest(
            ProgressionInput(
                history: history, repMin: range.lowerBound, repMax: range.upperBound, targetRir: targetRir,
                loadClass: loadClass, roundingStepKg: step
            )
        )
    }

    // MARK: Double progression

    @Test func noHistoryHasNoSuggestion() {
        #expect(suggest([]) == nil)
        #expect(suggest([[]]) == nil)
    }

    @Test func allSetsAtCeilingAddWeightAndResetReps() {
        let result = suggest([sets(60, [12, 12, 12])])
        #expect(result == ProgressionSuggestion(weightKg: 62.5, reps: 8, rationale: .addWeight(incrementKg: 2.5)))
    }

    @Test func lowerBodyCompoundJumpsBigger() {
        let result = suggest([sets(100, [8, 8, 8])], range: 5...8, loadClass: .lowerCompound)
        #expect(result == ProgressionSuggestion(weightKg: 105, reps: 5, rationale: .addWeight(incrementKg: 5)))
    }

    @Test func isolationStepNeverBelowPlateStep() {
        let result = suggest([sets(15, [15, 15, 15])], range: 12...15, loadClass: .isolation)
        #expect(result == ProgressionSuggestion(weightKg: 17.5, reps: 12, rationale: .addWeight(incrementKg: 2.5)))
        #expect(suggest([sets(15, [15, 15, 15])], range: 12...15, loadClass: .isolation, step: 1.25)?.weightKg == 16.25)
    }

    @Test func belowCeilingAddsOneRepToTheWeakestSet() {
        let result = suggest([sets(60, [12, 10, 9])])
        #expect(result == ProgressionSuggestion(weightKg: 60, reps: 10, rationale: .addRep))
    }

    @Test func oneSetShortOfCeilingStillOnlyAddsARep() {
        #expect(suggest([sets(60, [12, 12, 11])])?.reps == 12)
    }

    @Test func weightIsAlwaysAMultipleOfThePlateStep() throws {
        let pounds = 5 * 0.45359237
        let result = try #require(suggest([sets(61.23, [12, 12, 12])], step: pounds))
        let steps = result.weightKg / pounds
        #expect(abs(steps - steps.rounded()) < 1e-6)
        #expect(result.weightKg > 61.23)
    }

    @Test func bodyweightAddsReps() {
        #expect(suggest([sets(0, [10, 8, 8])]) == ProgressionSuggestion(weightKg: 0, reps: 9, rationale: .addRepBodyweight))
    }

    // MARK: RIR

    @Test func clearlyEasierThanTargetJumpsFasterAtCeiling() {
        let result = suggest([sets(60, [12, 12, 12], rir: 4)], targetRir: 2)
        #expect(result == ProgressionSuggestion(weightKg: 65, reps: 8, rationale: .addWeightFast(incrementKg: 5)))
    }

    @Test func clearlyEasierThanTargetAddsTwoRepsBelowCeiling() {
        let result = suggest([sets(60, [9, 9, 9], rir: 4)], targetRir: 2)
        #expect(result == ProgressionSuggestion(weightKg: 60, reps: 11, rationale: .addRepsFast))
        #expect(suggest([sets(60, [11, 11, 11], rir: 4)], targetRir: 2)?.reps == 12)
    }

    @Test func harderThanTargetHoldsEvenAtCeiling() {
        let result = suggest([sets(60, [12, 12, 12], rir: 0)], targetRir: 2)
        #expect(result == ProgressionSuggestion(weightKg: 60, reps: 12, rationale: .holdHard))
    }

    @Test func unsetTargetRirDefaultsToTwo() {
        #expect(suggest([sets(60, [12, 12, 12], rir: 4)])?.rationale == .addWeightFast(incrementKg: 5))
        #expect(suggest([sets(60, [12, 12, 12], rir: 0)])?.rationale == .holdHard)
        #expect(suggest([sets(60, [12, 12, 12], rir: 2)])?.rationale == .addWeight(incrementKg: 2.5))
    }

    @Test func missingRirIsOnTarget() {
        #expect(suggest([sets(60, [12, 12, 12])], targetRir: 3)?.rationale == .addWeight(incrementKg: 2.5))
    }

    // MARK: Regression and deload

    @Test func oneWorseSessionIsNotYetRecovery() {
        let result = suggest([sets(60, [8, 8, 8]), sets(60, [10, 10, 10])])
        #expect(result?.rationale == .addRep)
    }

    @Test func twoWorseSessionsHoldTheLoad() {
        // Newest first: 8s after 9s after 10s.
        let result = suggest([sets(60, [8, 8, 8]), sets(60, [9, 9, 9]), sets(60, [10, 10, 10])])
        #expect(result == ProgressionSuggestion(weightKg: 60, reps: 8, rationale: .recovery))
    }

    @Test func threeSessionsWithoutProgressDeloadByTenPercent() {
        let flat = sets(60, [10, 10, 10])
        let result = suggest([flat, flat, flat, flat], range: 8...12)
        #expect(result == ProgressionSuggestion(weightKg: 55, reps: 12, rationale: .deload))
    }

    @Test func threeRegressionsAreADeloadNotARecovery() {
        let history = [sets(60, [7, 7, 7]), sets(60, [8, 8, 8]), sets(60, [9, 9, 9]), sets(60, [10, 10, 10])]
        #expect(suggest(history)?.rationale == .deload)
    }

    @Test func aProgressingSessionBreaksTheStall() {
        let flat = sets(60, [10, 10, 10])
        let history = [flat, flat, sets(60, [10, 10, 10]), sets(60, [8, 8, 8])]
        // trends newest first: flat, flat, progress → no deload.
        #expect(suggest(history)?.rationale == .addRep)
    }

    @Test func fewerThanFourSessionsNeverDeload() {
        let flat = sets(60, [10, 10, 10])
        #expect(suggest([flat, flat, flat])?.rationale != .deload)
    }

    @Test func deloadNeverDropsBelowOnePlateStep() {
        let flat = sets(2.5, [10, 10, 10])
        #expect(suggest([flat, flat, flat, flat])?.weightKg == 2.5)
    }

    // MARK: Classification

    @Test func classifiesExercises() {
        #expect(LoadClass.classify(movementPattern: "squat", mechanic: "compound") == .lowerCompound)
        #expect(LoadClass.classify(movementPattern: "hip_hinge", mechanic: "compound") == .lowerCompound)
        #expect(LoadClass.classify(movementPattern: "horizontal_push", mechanic: "compound") == .upperCompound)
        #expect(LoadClass.classify(movementPattern: "isolation_biceps", mechanic: "isolation") == .isolation)
        #expect(LoadClass.classify(movementPattern: nil, mechanic: "isolation") == .isolation)
        #expect(LoadClass.classify(movementPattern: nil, mechanic: nil) == .upperCompound)
    }
}
