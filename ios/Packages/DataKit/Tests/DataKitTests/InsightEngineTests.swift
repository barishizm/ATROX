@testable import DataKit
import Foundation
import StrengthKit
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func fact(_ id: String, sessions: Int = 10, plateau: ProgressAnalyzer.PlateauStatus = .progressing, score: Double? = 50) -> ExerciseProgressFact {
    ExerciseProgressFact(exerciseId: id, sessionCount: sessions, plateau: plateau, progressScore: score, muscles: ["chest"])
}

private func kinds(_ inputs: InsightInputs) -> [InsightKind] { InsightEngine.candidates(inputs).map(\.kind) }

private func insight(
    _ kind: InsightKind = .plateau, subject: String = "bench", priority: Double = 50, severity: InsightSeverity = .mild, active: Bool = true,
    shown: Date? = nil, dismissed: Date? = nil
) -> Insight {
    Insight(
        id: InsightRecord.id(userId: testUser, kind: kind.rawValue, subject: subject), kind: kind, subject: subject, severity: severity,
        priority: priority, action: .askCoach, payload: InsightPayload(), isActive: active, detectedAt: now, lastShownAt: shown, dismissedAt: dismissed
    )
}

private func ago(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400 - 60) }

@Suite struct InsightRulesTests {
    @Test func quietInputsStaySilent() {
        let inputs = InsightInputs(
            exercises: [fact("bench"), fact("squat", score: 60)], weeklyMuscleSets: ["chest": [8, 9, 10, 9], "lats": [8, 8, 9, 8]],
            finishedWorkouts: 40, daysSinceLastWorkout: 3, bodyweightStaleDays: nil,
            repBands: RepBandCounts(strength: 20, hypertrophy: 40, endurance: 10)
        )
        #expect(InsightEngine.candidates(inputs).isEmpty)
        #expect(InsightEngine.candidates(InsightInputs()).isEmpty)
    }

    @Test func plateauNeedsEnoughSessionsAndRaisesSeverityWhenProgressIsSlow() {
        #expect(kinds(InsightInputs(exercises: [fact("bench", sessions: 5, plateau: .plateau)])).isEmpty)
        let mild = InsightEngine.candidates(InsightInputs(exercises: [fact("bench", plateau: .plateau, score: 45)]))
        #expect(mild.map(\.kind) == [.plateau] && mild.first?.severity == .mild && mild.first?.payload.subjects == ["bench"])
        let moderate = InsightEngine.candidates(InsightInputs(exercises: [fact("bench", plateau: .plateau, score: 20)]))
        #expect(moderate.first?.severity == .moderate)
        #expect((moderate.first?.priority ?? 0) > (mild.first?.priority ?? 0))
    }

    @Test func slowAndFastProgressUseTheScoreBoundsAndSkipPlateaus() {
        let candidates = InsightEngine.candidates(InsightInputs(exercises: [
            fact("slow", score: 20), fact("slower", score: 10), fact("fast", score: 90), fact("mid", score: 55),
            fact("flat", plateau: .plateau, score: 5), fact("young", sessions: 3, score: 5),
        ]))
        let byKind = Dictionary(grouping: candidates, by: \.kind)
        #expect(Set(byKind[.progressSlow]?.map(\.subject) ?? []) == ["slow", "slower"])
        #expect(byKind[.progressSlow]?.first { $0.subject == "slower" }?.severity == .moderate)
        #expect(byKind[.progressFast]?.map(\.subject) == ["fast"])
        #expect(byKind[.plateau]?.map(\.subject) == ["flat"])
    }

    @Test func perKindCapsKeepOnlyTheBest() {
        let facts = (0..<6).map { fact("e\($0)", plateau: .plateau, score: 40) }
        #expect(InsightEngine.candidates(InsightInputs(exercises: facts)).count == InsightThresholds.capPerKind[.plateau])
    }

    @Test func neglectedMuscleNeedsHistoryAndAnEmptyLastWeek() {
        let weekly: [String: [Double]] = [
            "lats": [8, 8, 8, 0],       // neglected, trained before
            "calves": [1, 1, 1, 0],     // never trained enough
            "chest": [8, 8, 8, 3],      // trained this week
            "biceps": [10, 8, 0, 0],    // two weeks away
        ]
        let found = InsightEngine.candidates(InsightInputs(weeklyMuscleSets: weekly)).filter { $0.kind == .neglectedMuscle }
        #expect(Set(found.map(\.subject)) == ["lats", "biceps"])
        #expect(found.first { $0.subject == "lats" }?.severity == .mild)
        #expect(found.first { $0.subject == "biceps" }?.severity == .moderate)
        #expect(found.allSatisfy { $0.action == .suggestExercises })
    }

    @Test func pushPullSpeaksOnlyForALargeGapAndNamesTheWeakSide() {
        func inputs(chest: Double, lats: Double) -> InsightInputs {
            InsightInputs(weeklyMuscleSets: ["chest": [chest, chest, chest, chest], "lats": [lats, lats, lats, lats]])
        }
        #expect(kinds(inputs(chest: 8, lats: 6)).isEmpty)
        let mild = InsightEngine.candidates(inputs(chest: 8, lats: 4.5)).first { $0.kind == .pushPull }
        #expect(mild?.severity == .mild && mild?.payload.variant == "pull_behind")
        let severe = InsightEngine.candidates(inputs(chest: 3, lats: 12)).first { $0.kind == .pushPull }
        #expect(severe?.payload.variant == "push_behind" && severe?.severity == .severe)
        #expect(kinds(InsightInputs(weeklyMuscleSets: ["chest": [1, 1, 1, 1], "lats": [0, 0, 0, 0]])).isEmpty)
    }

    @Test func comebackIgnoresNewUsersAndScalesWithTheBreak() {
        func level(days: Int, workouts: Int) -> InsightSeverity? {
            InsightEngine.candidates(InsightInputs(finishedWorkouts: workouts, daysSinceLastWorkout: days)).first { $0.kind == .comeback }?.severity
        }
        #expect(level(days: 13, workouts: 20) == nil)
        #expect(level(days: 14, workouts: 20) == .mild)
        #expect(level(days: 35, workouts: 20) == .moderate)
        #expect(level(days: 90, workouts: 20) == .severe)
        #expect(level(days: 90, workouts: 2) == nil)
    }

    @Test func staleBodyweightAndRepRangeThresholds() {
        #expect(kinds(InsightInputs(bodyweightStaleDays: nil)).isEmpty)
        #expect(InsightEngine.candidates(InsightInputs(bodyweightStaleDays: 70)).first?.action == .updateBodyweight)
        #expect(kinds(InsightInputs(repBands: RepBandCounts(strength: 28, hypertrophy: 2, endurance: 0))) == [.repRangeStuck])
        let stuck = InsightEngine.candidates(InsightInputs(repBands: RepBandCounts(strength: 2, hypertrophy: 38, endurance: 0))).first
        #expect(stuck?.payload.variant == "hypertrophy" && stuck?.severity == .moderate)
        #expect(kinds(InsightInputs(repBands: RepBandCounts(strength: 3, hypertrophy: 20, endurance: 1))).isEmpty)  // too few sets
        #expect(kinds(InsightInputs(repBands: RepBandCounts(strength: 10, hypertrophy: 20, endurance: 10))).isEmpty)
    }

    @Test func candidatesAreSortedByPriorityThenKindAndSubject() {
        let inputs = InsightInputs(
            exercises: [fact("a", plateau: .plateau, score: 40), fact("b", plateau: .plateau, score: 10)],
            finishedWorkouts: 20, daysSinceLastWorkout: 20
        )
        let list = InsightEngine.candidates(inputs)
        #expect(list.map(\.priority) == list.map(\.priority).sorted(by: >))
        #expect(list.first?.kind == .comeback)
        #expect(InsightEngine.candidates(inputs) == list)
    }

    @Test func payloadSurvivesItsJSONForm() {
        let payload = InsightPayload(subjects: ["bench"], muscles: ["lats"], values: ["ratio": 1.75], variant: "pull_behind")
        #expect(InsightPayload(json: payload.json) == payload)
        #expect(InsightPayload(json: "not json") == InsightPayload())
    }

    @Test func realImbalanceFindingsBecomeInsightsAndReplaceTheVolumeRule() throws {
        let model = try EmbeddedModelBundle.model()
        let analyzer = try ImbalanceAnalyzer(params: model.params.imbalance, correlation: model.params.correlation)
        let scores = [
            ImbalanceAnalyzer.ScoreInput(exerciseId: "bench", z: 1.5, confidence: .high, pattern: "horizontal_push", muscles: ["chest"]),
            ImbalanceAnalyzer.ScoreInput(exerciseId: "row", z: -1.2, confidence: .high, pattern: "horizontal_pull", muscles: ["lats"]),
        ]
        let findings = try analyzer.analyze(scores)
        let ratio = try #require(findings.first { $0.kind == .ratioRule && $0.ruleId == "push_pull" })
        let inputs = InsightInputs(imbalances: findings, weeklyMuscleSets: ["chest": [8, 8, 8, 8], "lats": [2, 2, 2, 2]])
        let found = InsightEngine.candidates(inputs)
        let item = try #require(found.first { $0.kind == .imbalance && $0.subject == "ratio_rule.push_pull" })
        #expect(item.payload.subjects == ["row"] && item.payload.variant == ratio.recommendationKey && item.action == .suggestExercises)
        #expect(!found.contains { $0.kind == .pushPull })
    }
}

@Suite struct InsightSelectorTests {
    @Test func aShownInsightStaysForTheDayThenRestsForFourteenDays() {
        #expect(InsightSelector.isEligible(insight(shown: nil), now: now, calendar: utc))
        #expect(InsightSelector.isEligible(insight(shown: now.addingTimeInterval(-3_600)), now: now, calendar: utc))
        #expect(!InsightSelector.isEligible(insight(shown: ago(1)), now: now, calendar: utc))
        #expect(!InsightSelector.isEligible(insight(shown: ago(13)), now: now, calendar: utc))
        #expect(InsightSelector.isEligible(insight(shown: ago(14)), now: now, calendar: utc))
    }

    @Test func dismissedInsightsStayAwayForSixtyDays() {
        #expect(!InsightSelector.isEligible(insight(dismissed: ago(1)), now: now, calendar: utc))
        #expect(!InsightSelector.isEligible(insight(dismissed: ago(59)), now: now, calendar: utc))
        #expect(InsightSelector.isEligible(insight(dismissed: ago(60)), now: now, calendar: utc))
        #expect(!InsightSelector.isEligible(insight(active: false), now: now, calendar: utc))
    }

    @Test func topPicksTheHighestPriorityEligibleOne() {
        let list = [
            insight(.plateau, subject: "a", priority: 50), insight(.comeback, subject: "global", priority: 70, shown: ago(3)),
            insight(.imbalance, subject: "r", priority: 62), insight(.neglectedMuscle, subject: "lats", priority: 80, dismissed: ago(2)),
        ]
        #expect(InsightSelector.top(list, now: now, calendar: utc)?.subject == "r")
        #expect(InsightSelector.top([insight(shown: ago(2))], now: now, calendar: utc) == nil)
        #expect(InsightSelector.top([], now: now, calendar: utc) == nil)
    }

    @Test func currentHidesDismissedAndInactiveWhileHistoryKeepsThem() {
        let live = insight(.plateau, subject: "a", priority: 55, shown: ago(5))
        let dismissed = insight(.imbalance, subject: "b", dismissed: ago(3))
        let gone = insight(.comeback, subject: "global", active: false)
        let all = [gone, live, dismissed]
        #expect(InsightSelector.current(all, now: now, calendar: utc).map(\.subject) == ["a"])
        #expect(Set(InsightSelector.history(all, now: now, calendar: utc).map(\.subject)) == ["b", "global"])
    }
}

@Suite struct InsightSuggestionsTests {
    private func item(_ id: String, _ muscles: [String], scorable: Bool = true, custom: Bool = false) -> ExerciseListItem {
        ExerciseListItem(id: id, nameEn: id.capitalized, nameTr: id, primaryMuscles: muscles, isScorable: scorable, isCustom: custom)
    }

    @Test func prefersScorableThenWiderCoverageThenName() {
        let items = [
            item("row", ["lats", "middle_back"]), item("pullup", ["lats"]), item("shrug", ["traps"], scorable: false),
            item("curl", ["biceps"]), item("custom-row", ["lats"], custom: true), item("bench", ["chest"]),
        ]
        let picked = InsightSuggestions.pick(from: items, muscles: ["lats", "middle_back", "traps"], limit: 3).map(\.id)
        #expect(picked == ["row", "pullup", "shrug"])
    }

    @Test func respectsExcludesLimitAndEmptyTargets() {
        let items = [item("row", ["lats"]), item("pullup", ["lats"]), item("pulldown", ["lats"])]
        #expect(InsightSuggestions.pick(from: items, muscles: ["lats"], exclude: ["row"], limit: 1).map(\.id) == ["pulldown"])
        #expect(InsightSuggestions.pick(from: items, muscles: [], limit: 3).isEmpty)
        #expect(InsightSuggestions.pick(from: items, muscles: ["calves"], limit: 3).isEmpty)
    }
}
