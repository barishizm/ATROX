import Testing
@testable import StrengthKit

@Suite struct EpleyEstimatorTests {
    @Test func singleRepReturnsWeight() {
        #expect(EpleyEstimator().estimateOneRepMax(weightKg: 100, reps: 1) == 100)
    }

    @Test func multipleRepsFollowEpley() throws {
        let value = try #require(EpleyEstimator().estimateOneRepMax(weightKg: 100, reps: 5))
        #expect(abs(value - 116.6667) < 1e-3)
    }

    @Test func invalidInputReturnsNil() {
        #expect(EpleyEstimator().estimateOneRepMax(weightKg: 0, reps: 5) == nil)
        #expect(EpleyEstimator().estimateOneRepMax(weightKg: 80, reps: 0) == nil)
    }
}
