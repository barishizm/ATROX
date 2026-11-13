// swiftlint:disable identifier_name
import Foundation
import Testing
@testable import StrengthKit

@Suite struct RecordMathTests {
    private let day: TimeInterval = 86_400

    private func set(_ day: Int, _ kg: Double, _ reps: Int, rir: Int? = nil, order: Int = 0) -> RecordSet {
        RecordSet(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), order: order, weightKg: kg, reps: reps, rir: rir)
    }

    @Test func firstSetOnlySetsTheBoard() {
        let first = set(0, 100, 5)
        let replay = RecordMath.replay([first])
        #expect(replay.breaks.isEmpty)
        #expect(Set(replay.board.map(\.metric)) == Set(RecordMetric.allCases))
    }

    @Test func heavierSetBreaksWeightE1rmAndVolume() throws {
        let a = set(0, 100, 5)
        let b = set(1, 105, 5)
        let replay = RecordMath.replay([a, b])
        let metrics = try #require(replay.breaks[b.id]).map(\.metric)
        #expect(metrics == [.weight, .e1rm, .volume])
    }

    @Test func tieIsNotARecord() {
        let a = set(0, 100, 5)
        let b = set(1, 100, 5)
        #expect(RecordMath.replay([a, b]).breaks.isEmpty)
    }

    @Test func moreRepsAtSameWeightIsARepsRecord() throws {
        let a = set(0, 100, 5)
        let b = set(1, 100, 6)
        let breaks = try #require(RecordMath.replay([a, b]).breaks[b.id])
        #expect(breaks.contains { $0.metric == .reps && $0.previousValue == 5 })
    }

    @Test func lighterSetWithMoreRepsBeatsOnlyHeavierOrEqualMarks() throws {
        let a = set(0, 100, 5)
        let b = set(1, 60, 12)
        let breaks = try #require(RecordMath.replay([a, b]).breaks[b.id])
        #expect(breaks.map(\.metric) == [.volume, .reps])
    }

    @Test func lighterSetWithFewerRepsIsDominated() {
        let a = set(0, 100, 8)
        let b = set(1, 80, 6)
        #expect(RecordMath.replay([a, b]).breaks[b.id] == nil)
    }

    @Test func newHeavierWeightWithFewRepsIsNotARepsRecord() throws {
        let a = set(0, 60, 12)
        let b = set(1, 100, 1)
        let metrics = try #require(RecordMath.replay([a, b]).breaks[b.id]).map(\.metric)
        #expect(!metrics.contains(.reps))
        #expect(metrics.contains(.weight))
    }

    @Test func bodyweightSetsOnlyTrackReps() throws {
        let a = set(0, 0, 10)
        let b = set(1, 0, 12)
        let replay = RecordMath.replay([a, b])
        #expect(replay.board.map(\.metric) == [.reps])
        #expect(try #require(replay.breaks[b.id]).map(\.metric) == [.reps])
    }

    @Test func outlierFlagsE1rmJumpOverTwelvePercent() throws {
        let a = set(0, 100, 5)
        let b = set(1, 130, 5)
        let breaks = try #require(RecordMath.replay([a, b]).breaks[b.id])
        #expect(breaks.first { $0.metric == .e1rm }?.isOutlier == true)
        let c = set(2, 105, 5)
        let small = try #require(RecordMath.replay([a, c]).breaks[c.id])
        #expect(small.first { $0.metric == .e1rm }?.isOutlier == false)
    }

    @Test func replayIsOrderIndependentOfInput() {
        let a = set(0, 100, 5)
        let b = set(1, 105, 5)
        let c = set(2, 110, 3)
        #expect(RecordMath.replay([c, a, b]) == RecordMath.replay([a, b, c]))
    }

    @Test func removingTheBestSetFallsBackToTheNextBest() throws {
        let a = set(0, 100, 5)
        let b = set(1, 110, 5)
        let board = RecordMath.replay([a]).board
        #expect(board.first { $0.metric == .weight }?.setId == a.id)
        #expect(RecordMath.replay([a, b]).board.first { $0.metric == .weight }?.setId == b.id)
    }

    @Test func sameDaySetsAreOrdered() throws {
        let a = set(0, 100, 5, order: 0)
        let b = set(0, 102.5, 5, order: 1)
        #expect(RecordMath.replay([b, a]).breaks[b.id] != nil)
        #expect(RecordMath.replay([b, a]).breaks[a.id] == nil)
    }

    @Test func invalidSetsAreIgnored() {
        #expect(RecordMath.value(.weight, of: set(0, 100, 0)) == nil)
        #expect(RecordMath.value(.e1rm, of: set(0, 100, 30)) == nil)
    }
}

@Suite struct E1RMConfidenceTests {
    private let model = E1RMModel.standard

    @Test func confidenceCurve() {
        #expect(model.confidence(effectiveReps: 3, rirKnown: true, isWarmup: false) == 1)
        #expect(abs(model.confidence(effectiveReps: 12, rirKnown: true, isWarmup: false) - 0.6) < 1e-9)
        #expect(abs(model.confidence(effectiveReps: 20, rirKnown: true, isWarmup: false) - 0.25) < 1e-9)
        #expect(model.confidence(effectiveReps: 30, rirKnown: true, isWarmup: false) == 0)
        #expect(abs(model.confidence(effectiveReps: 3, rirKnown: false, isWarmup: false) - 0.85) < 1e-9)
        #expect(model.confidence(effectiveReps: 3, rirKnown: true, isWarmup: true) == 0)
    }

    @Test func rirRaisesEffectiveReps() throws {
        let plain = try #require(model.estimate(weightKg: 100, reps: 5))
        let withRir = try #require(model.estimate(weightKg: 100, reps: 5, rir: 2))
        #expect(withRir.valueKg > plain.valueKg)
        #expect(model.estimate(weightKg: 100, reps: 1)?.valueKg == 100)
        #expect(model.estimate(weightKg: 100, reps: 30) == nil)
        #expect(model.estimate(weightKg: 0, reps: 5) == nil)
        #expect(model.estimate(weightKg: 80, reps: 0) == nil)
    }

    @Test func categoriesFollowMovementPattern() {
        #expect(model.category(for: "squat") == "lower_compound")
        #expect(model.category(for: "isolation_biceps") == "isolation")
        #expect(model.category(for: "core") == model.params.defaultCategory)
        #expect(model.category(for: nil) == model.params.defaultCategory)
    }
}
