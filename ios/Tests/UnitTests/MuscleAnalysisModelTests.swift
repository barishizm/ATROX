import DataKit
import DesignSystem
import Foundation
import Testing

@testable import ATROX

@MainActor
@Suite struct MuscleAnalysisModelTests {
    private func row(_ muscle: Muscle, score: Double?, sets: Double = 0, weak: Bool = false) -> MuscleAnalysisModel.Row {
        MuscleAnalysisModel.Row(muscle: muscle, score: score, sets: sets, change: nil, isWeak: weak)
    }

    @Test func rowsCoverEveryMuscleAndCarryTheLastSevenDaysOfSets() {
        let report = MuscleReport(last7Days: ["chest": 7.5, "lats": 4], weekly: [:])
        let rows = MuscleAnalysisModel.rows(overview: nil, report: report, changes: [:])
        #expect(rows.count == Muscle.allCases.count)
        #expect(rows.first { $0.muscle == .chest }?.sets == 7.5)
        #expect(rows.first { $0.muscle == .calves }?.sets == 0)
        #expect(rows.allSatisfy { $0.score == nil && !$0.isWeak })
    }

    @Test func scoreModeListsBestFirstAndUnscoredLast() {
        let rows = [row(.calves, score: nil), row(.chest, score: 40), row(.lats, score: 72), row(.biceps, score: nil), row(.glutes, score: 40)]
        let sorted = MuscleAnalysisModel.sorted(rows, mode: .score).map(\.muscle)
        #expect(sorted == [.lats, .chest, .glutes, .biceps, .calves])
    }

    @Test func loadModeListsTheMostNeglectedFirst() {
        let rows = [row(.chest, score: 50, sets: 9), row(.calves, score: nil, sets: 0), row(.lats, score: 60, sets: 3), row(.biceps, score: nil, sets: 0)]
        let sorted = MuscleAnalysisModel.sorted(rows, mode: .load).map(\.muscle)
        #expect(sorted == [.biceps, .calves, .lats, .chest])
    }
}
