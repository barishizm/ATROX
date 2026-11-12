import Testing
@testable import StrengthKit

@Suite struct PlateCalculatorTests {
    private func stock(_ pairs: [(Double, Int)]) -> [PlateStock] { pairs.map { PlateStock(weight: $0.0, pairs: $0.1) } }

    @Test func hundredKgOnTwentyBarUsesTwentyFifteenFiveWhenOnlyOnePairOfEach() {
        let owned = stock([(20, 1), (15, 1), (10, 1), (5, 1), (2.5, 1)])
        let solution = PlateCalculator.solve(target: 100, bar: 20, stock: owned)
        #expect(solution.isExact)
        #expect(solution.lower.platesPerSide == [20, 15, 5])
        #expect(solution.lower.total == 100)
    }

    @Test func fewestPlatesWinWithPlentyOfStock() {
        let solution = PlateCalculator.solve(target: 100, bar: 20, stock: PlateDefaults.stock(for: .kilograms))
        #expect(solution.lower.platesPerSide == [20, 20])
    }

    @Test func emptyBarTargetNeedsNoPlates() {
        let solution = PlateCalculator.solve(target: 20, bar: 20, stock: PlateDefaults.stock(for: .kilograms))
        #expect(solution.isExact)
        #expect(solution.lower.platesPerSide.isEmpty)
    }

    @Test func belowBarFallsBackToBarAndOffersNextLoad() {
        let solution = PlateCalculator.solve(target: 15, bar: 20, stock: PlateDefaults.stock(for: .kilograms))
        #expect(solution.isBelowBar)
        #expect(!solution.isExact)
        #expect(solution.lower.total == 20)
        #expect(solution.upper?.total == 22.5)
    }

    @Test func singlePlatePairLimitsReach() {
        let solution = PlateCalculator.solve(target: 100, bar: 20, stock: stock([(20, 1)]))
        #expect(!solution.isExact)
        #expect(solution.lower.total == 60)
        #expect(solution.upper == nil)
    }

    @Test func unreachableTargetOffersLowerAndUpperNeighbours() {
        // 1.25 kg plates: 21 kg is not reachable on a 20 kg bar with 2.5 kg steps.
        let solution = PlateCalculator.solve(target: 101, bar: 20, stock: stock([(25, 2), (20, 2), (15, 2), (10, 2), (5, 2), (2.5, 2)]))
        #expect(solution.lower.total == 100)
        #expect(solution.upper?.total == 105)
        #expect(solution.best.total == 100)
    }

    @Test func poundPlatesRoundTripWithFortyFiveBar() {
        let solution = PlateCalculator.solve(target: 225, bar: 45, stock: PlateDefaults.stock(for: .pounds))
        #expect(solution.isExact)
        #expect(solution.lower.platesPerSide == [45, 45])
        let odd = PlateCalculator.solve(target: 137, bar: 45, stock: PlateDefaults.stock(for: .pounds))
        #expect(odd.lower.total == 135)
        #expect(odd.upper?.total == 140)
    }

    @Test func noPlatesOwnedOnlyHasTheBar() {
        let solution = PlateCalculator.solve(target: 60, bar: 20, stock: [])
        #expect(solution.lower.total == 20)
        #expect(solution.upper == nil)
    }

    @Test func barTypesKnowTheirWeights() {
        #expect(BarType.olympic20.weight(in: .kilograms) == 20)
        #expect(BarType.olympic20.weight(in: .pounds) == 45)
        #expect(BarType.custom.weight(in: .kilograms) == nil)
    }
}

@Suite struct WarmupGeneratorTests {
    @Test func rampForHundredKgOnTwentyBar() {
        let sets = WarmupGenerator.sets(workingWeight: 100, bar: 20, increment: 2.5)
        #expect(sets.map(\.weight) == [20, 40, 60, 80])
        #expect(sets.map(\.reps) == [10, 8, 5, 3])
    }

    @Test func lightWeightsDropDuplicatesAndStayBelowWorking() {
        let sets = WarmupGenerator.sets(workingWeight: 30, bar: 20, increment: 2.5)
        #expect(sets.map(\.weight) == [20, 25])
        #expect(sets.allSatisfy { $0.weight < 30 })
    }

    @Test func workingWeightAtOrBelowBarHasNoWarmups() {
        #expect(WarmupGenerator.sets(workingWeight: 20, bar: 20, increment: 2.5).isEmpty)
        #expect(WarmupGenerator.sets(workingWeight: 0, bar: 20, increment: 2.5).isEmpty)
    }

    @Test func barlessExerciseStartsAtFirstPercentage() {
        let sets = WarmupGenerator.sets(workingWeight: 50, bar: 0, increment: 2.5)
        #expect(sets.map(\.weight) == [20, 30, 40])
    }

    @Test func poundsRoundToFivePounds() {
        let sets = WarmupGenerator.sets(workingWeight: 225, bar: 45, increment: 5)
        #expect(sets.map(\.weight) == [45, 90, 135, 180])
    }
}
