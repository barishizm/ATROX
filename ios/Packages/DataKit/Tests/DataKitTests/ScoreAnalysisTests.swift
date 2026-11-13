@testable import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

private let gregorian: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private let roles: [String: MuscleRoles] = [
    "bench": MuscleRoles(primary: ["chest"], secondary: ["triceps", "shoulders"]),
    "row": MuscleRoles(primary: ["lats", "middle_back"], secondary: ["biceps"]),
    "dip": MuscleRoles(primary: ["triceps", "chest"], secondary: ["chest", "shoulders"]),
]

@Suite struct MuscleVolumeTests {
    @Test func primaryCountsOneAndSecondaryHalf() {
        let sets = MuscleVolume.sets([VolumeEntry(day: 100, exerciseId: "bench", sets: 4)], roles: roles, days: 100...100)
        #expect(sets["chest"] == 4)
        #expect(sets["triceps"] == 2)
        #expect(sets["shoulders"] == 2)
        #expect(sets["lats"] == nil)
    }

    @Test func aMuscleInBothListsCountsAsPrimaryOnly() {
        let sets = MuscleVolume.sets([VolumeEntry(day: 5, exerciseId: "dip", sets: 3)], roles: roles, days: 0...10)
        #expect(sets["chest"] == 3)
        #expect(sets["triceps"] == 3)
        #expect(sets["shoulders"] == 1.5)
    }

    @Test func sumsAcrossExercisesAndIgnoresOutOfRangeAndUnknown() {
        let entries = [
            VolumeEntry(day: 100, exerciseId: "bench", sets: 3), VolumeEntry(day: 99, exerciseId: "dip", sets: 2),
            VolumeEntry(day: 90, exerciseId: "bench", sets: 9), VolumeEntry(day: 100, exerciseId: "custom", sets: 5),
            VolumeEntry(day: 100, exerciseId: "row", sets: 0),
        ]
        let sets = MuscleVolume.sets(entries, roles: roles, days: 94...100)
        #expect(sets["chest"] == 5)
        #expect(sets["triceps"] == 3 * 0.5 + 2)
        #expect(sets["lats"] == nil)
    }

    @Test func weeklyWindowsAreSevenDaysEndingToday() {
        let entries = [
            VolumeEntry(day: 100, exerciseId: "bench", sets: 2), VolumeEntry(day: 94, exerciseId: "bench", sets: 1),
            VolumeEntry(day: 93, exerciseId: "bench", sets: 4), VolumeEntry(day: 73, exerciseId: "bench", sets: 8),
            VolumeEntry(day: 72, exerciseId: "bench", sets: 16),
        ]
        let weekly = MuscleVolume.weekly(entries, roles: roles, endDay: 100, weeks: 4)
        #expect(weekly["chest"] == [8, 0, 4, 3])
        #expect(weekly["lats"] == nil)
    }
}

@Suite struct ScoreAnalysisTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ offset: Int) -> Date { gregorian.date(byAdding: .day, value: -offset, to: now)! }

    @Test func weakestNeedsMoreMusclesThanTheCount() {
        #expect(MuscleRanking.weakest(["a": 10, "b": 20, "c": 30]).isEmpty)
        #expect(MuscleRanking.weakest(["a": 50, "b": 20, "c": 30, "d": 40, "e": 10]) == ["e", "b", "c"])
        #expect(MuscleRanking.weakest(["b": 10, "a": 10, "c": 30, "d": 40], count: 2) == ["a", "b"])
    }

    @Test func changeComparesWithTheLastPointOlderThanTheWindow() {
        let series = [ScorePoint(date: day(60), score: 40), ScorePoint(date: day(35), score: 44), ScorePoint(date: day(10), score: 50), ScorePoint(date: day(0), score: 52)]
        #expect(ScoreTrend.change(series, now: now, days: 30, calendar: gregorian) == 8)
        #expect(ScoreTrend.change(series, current: 60, now: now, days: 30, calendar: gregorian) == 16)
    }

    @Test func changeFallsBackToTheFirstPointOfAYoungSeriesAndNeedsAWeek() {
        let young = [ScorePoint(date: day(14), score: 30), ScorePoint(date: day(0), score: 33)]
        #expect(ScoreTrend.change(young, now: now, days: 30, calendar: gregorian) == 3)
        let tooYoung = [ScorePoint(date: day(3), score: 30), ScorePoint(date: day(0), score: 33)]
        #expect(ScoreTrend.change(tooYoung, now: now, days: 30, calendar: gregorian) == nil)
        #expect(ScoreTrend.change([], now: now, calendar: gregorian) == nil)
    }

    @Test func mostImprovedPicksTheBiggestGainAboveTheMinimum() {
        let series = [
            "squat": [ScorePoint(date: day(40), score: 30), ScorePoint(date: day(0), score: 34)],
            "bench": [ScorePoint(date: day(40), score: 50), ScorePoint(date: day(0), score: 58)],
            "row": [ScorePoint(date: day(40), score: 50), ScorePoint(date: day(0), score: 50.4)],
        ]
        let best = ScoreTrend.mostImproved(series, now: now, calendar: gregorian)
        #expect(best?.key == "bench")
        #expect(best?.change == 8)
        #expect(ScoreTrend.mostImproved(["row": series["row"]!], now: now, calendar: gregorian) == nil)
    }

    @Test func weeklyCountsBucketByCalendarWeek() {
        let current = gregorian.dateInterval(of: .weekOfYear, for: now)!.start
        let dates = [
            current.addingTimeInterval(3_600), current.addingTimeInterval(86_400 * 2),
            current.addingTimeInterval(-86_400), current.addingTimeInterval(-86_400 * 8),
            current.addingTimeInterval(-86_400 * 40),
        ]
        #expect(WeeklyActivity.counts(dates, now: now, weeks: 3, calendar: gregorian) == [1, 1, 2])
        #expect(WeeklyActivity.counts([], now: now, weeks: 0, calendar: gregorian).isEmpty)
    }

    @Test func streakCountsMetWeeksAndDoesNotBreakOnTheOpenWeek() {
        #expect(WeeklyActivity.streak(counts: [0, 3, 3, 4, 1], goal: 3) == 3)
        #expect(WeeklyActivity.streak(counts: [0, 3, 3, 4, 3], goal: 3) == 4)
        #expect(WeeklyActivity.streak(counts: [3, 3, 2, 3, 0], goal: 3) == 1)
        #expect(WeeklyActivity.streak(counts: [], goal: 3) == 0)
        #expect(WeeklyActivity.streak(counts: [1, 1], goal: 0) == 2)
    }

    @Test func dashboardStatusMapsNoDataProvisionalAndFull() {
        let patterns = ["horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull", "squat", "hip_hinge", "core"]
        #expect(DashboardStatus.make(overall: nil, allPatterns: patterns) == .noData)
        #expect(DashboardStatus.make(hasOverall: true, provisional: true, covered: ["horizontal_push", "squat"], allPatterns: patterns)
            == .provisional(missing: ["vertical_push", "horizontal_pull", "vertical_pull", "hip_hinge", "core"]))
        #expect(DashboardStatus.make(hasOverall: true, provisional: false, covered: patterns, allPatterns: patterns) == .full)
    }

    @Test func everyPatternHasASuggestedExercise() {
        for pattern in ["horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull", "squat", "hip_hinge", "core"] {
            #expect(PatternSuggestion.exerciseId(for: pattern) != nil)
        }
        #expect(PatternSuggestion.exerciseId(for: "carry") == nil)
        #expect(PatternSuggestion.first(missing: ["squat", "core"]) == "squat")
    }

    @Test func nextWorkoutPrefersTodaysPlanThenTheDayAfterTheLastOne() {
        let ids = (0..<3).map { _ in UUID() }
        let days = ids.enumerated().map { RoutineDaySnapshot(id: $1, routineId: UUID(), position: $0, name: "D\($0)", exercises: []) }
        let routine = RoutineSnapshot(
            id: UUID(), userId: UUID(), name: "R", notes: nil, createdAt: now, updatedAt: now, syncState: .pending, days: days
        )
        #expect(NextWorkout.pick(routine: routine, weekdayPlan: [2: ids[2]], weekday: 2, lastDayId: ids[0])?.id == ids[2])
        #expect(NextWorkout.pick(routine: routine, weekdayPlan: [2: ids[2]], weekday: 3, lastDayId: ids[0])?.id == ids[1])
        #expect(NextWorkout.pick(routine: routine, weekdayPlan: [:], weekday: 3, lastDayId: ids[2])?.id == ids[0])
        #expect(NextWorkout.pick(routine: routine, weekdayPlan: [:], weekday: 3, lastDayId: nil)?.id == ids[0])
        #expect(NextWorkout.pick(routine: routine, weekdayPlan: [4: UUID()], weekday: 4, lastDayId: ids[1])?.id == ids[2])
    }
}

@Suite struct ScoreAnalysisModelTests {
    private let user = ScoringUser(sex: .male, age: 30, bodyweightKg: 80)

    private func overview(_ sets: [String: [ScoringSet]]) throws -> (ScoreOverview, StrengthModel) {
        let model = try EmbeddedModelBundle.model()
        let scoring = ScoringModel(model: model, version: "test")
        let scored = sets.mapValues { $0.map { ScoredSet(set: $0) } }
        return (ScoreCalculator.compute(sets: scored, scoring: scoring, user: user, population: .gym, asOfDay: 20_000), model)
    }

    private func benchSets() -> [ScoringSet] {
        (0..<6).map { ScoringSet(day: 20_000 - 3 * $0, weightKg: 80, reps: 5, rir: 1, isWarmup: false) }
    }

    @Test func muscleContributionsListTheExercisesThatFeedAMuscle() throws {
        let (result, model) = try overview(["barbell-bench-press-medium-grip": benchSets()])
        let chest = MuscleContributions.contributions(muscle: "chest", overview: result, model: model)
        #expect(chest.map(\.exerciseId) == ["barbell-bench-press-medium-grip"])
        #expect(chest.first?.role == .primary)
        #expect(chest.first?.share == 1)
        let triceps = MuscleContributions.contributions(muscle: "triceps", overview: result, model: model)
        #expect(triceps.first?.role == .secondary)
        #expect(MuscleContributions.contributions(muscle: "calves", overview: result, model: model).isEmpty)
    }

    @Test func sharesFollowTheModelsRoleWeights() throws {
        let squat = (0..<6).map { ScoringSet(day: 20_000 - 3 * $0, weightKg: 100, reps: 5, rir: 1, isWarmup: false) }
        let (result, model) = try overview(["barbell-bench-press-medium-grip": benchSets(), "barbell-full-squat": squat])
        let weights = model.params.aggregate.muscleWeights
        let shoulders = MuscleContributions.contributions(muscle: "shoulders", overview: result, model: model)
        let total = shoulders.reduce(0) { $0 + $1.share }
        #expect(abs(total - 1) < 1e-9)
        #expect(weights.primary > weights.secondary)
    }

    @Test func overviewExposesPatternScoresAndASinglePatternEqualsTheOverallScore() throws {
        let (result, _) = try overview(["barbell-bench-press-medium-grip": benchSets()])
        #expect(Set(result.patterns.keys) == ["horizontal_push"])
        let overall = try #require(result.overall)
        #expect(abs(try #require(result.patterns["horizontal_push"]).score - overall.score) < 1e-9)
        #expect(overall.provisional)
        #expect(DashboardStatus.make(overall: overall, allPatterns: ["horizontal_push", "squat"]) == .provisional(missing: ["squat"]))
    }
}

@Suite struct TrainingStatsTests {
    @Test func dashboardCountsFinishedWorkoutsAndTheStreakFromHistory() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let workouts = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: clock.now) }
        let history = TrainingFixtures.twelveWeekHistory(now: clock.now)
        for draft in history { try await workouts.start(draft, userId: testUser) }
        let stats = TrainingStats(modelContainer: container, clock: clock.closure, calendar: Calendar(identifier: .gregorian))
        let facts = await stats.dashboard(userId: testUser, population: .gym, overallScore: nil)
        #expect(facts.finishedWorkouts == history.count)
        #expect((0...TrainingStats.streakLookbackWeeks).contains(facts.streakWeeks))
        #expect(facts.goal == 4)
        #expect(facts.overallChange == nil)
        let custom = await stats.dashboard(userId: testUser, population: .gym, overallScore: nil, goal: 2)
        #expect(custom.goal == 2)
        let report = await stats.muscleReport(userId: testUser)
        #expect(report.weekly.values.allSatisfy { $0.count == 4 })
    }
}
