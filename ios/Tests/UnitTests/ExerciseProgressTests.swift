import DataKit
import Foundation
import SwiftData
import Testing

@testable import ATROX

@MainActor
@Suite struct ExerciseProgressTests {
    private typealias Point = ExerciseHistoryModel.ChartPoint
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(daysAgo: Int, _ value: Double) -> Point {
        Point(date: now.addingTimeInterval(Double(-daysAgo) * 86_400), value: value)
    }

    @Test func rangeKeepsOnlyThePointsInsideTheWindow() {
        let points = [point(daysAgo: 200, 40), point(daysAgo: 60, 50), point(daysAgo: 10, 55), point(daysAgo: 1, 60)]
        #expect(ExerciseHistoryModel.window(points, days: 30, now: now).map(\.value) == [55, 60])
        #expect(ExerciseHistoryModel.window(points, days: 90, now: now).map(\.value) == [50, 55, 60])
        #expect(ExerciseHistoryModel.window(points, days: nil, now: now).count == 4)
        #expect(ExerciseHistoryModel.window([], days: 30, now: now).isEmpty)
    }

    @Test func chartSpanCoversEmptyAndSinglePointHistories() {
        let empty = ExerciseHistoryView.xDomain([], days: 30, now: now)
        #expect(empty.upperBound == now && empty.lowerBound == now.addingTimeInterval(-30 * 86_400))
        let one = ExerciseHistoryView.xDomain([point(daysAgo: 2, 60)], days: 30, now: now)
        #expect(one.lowerBound < one.upperBound)
        let two = ExerciseHistoryView.xDomain([point(daysAgo: 9, 50), point(daysAgo: 1, 60)], days: 30, now: now)
        #expect(two.upperBound.timeIntervalSince(two.lowerBound) == 8 * 86_400)
    }

    @Test func rangesMapToTheirDayCounts() {
        #expect(ProgressRange.month.days == 30)
        #expect(ProgressRange.quarter.days == 90)
        #expect(ProgressRange.all.days == nil)
    }

    @Test func displayedRirPrefersTheHalfStepAndFallsBackToTheWholeNumber() {
        let half = SetInput.logged(weightKg: 60, reps: 5, rir: 1.5)
        #expect(ExerciseHistoryModel.rir(of: half) == 1.5)
        let whole = SetInput.logged(weightKg: 60, reps: 5, rir: 2)
        #expect(ExerciseHistoryModel.rir(of: whole) == 2)
        #expect(ExerciseHistoryModel.rir(of: SetInput(weightKg: 60, reps: 5)) == nil)
        // A set typed in the live workout only has the whole number.
        #expect(ExerciseHistoryModel.rir(of: SetInput(weightKg: 60, reps: 5, rir: 3)) == 3)
    }

    @Test func oneDayProgramsOpenTheirDayAndLongerOnesTheProgram() async throws {
        let repo = SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: { Date() })
        let user = UUID()
        let routine = try await repo.create(name: "Push", notes: nil, userId: user)
        try await repo.addDay(routineId: routine.id, name: "Push")
        let single = try #require(try await repo.all(userId: user).first)
        #expect(WorkoutRootView.destination(of: single) == .routineDay(routineId: single.id, dayId: single.days[0].id))
        try await repo.addDay(routineId: routine.id, name: "Pull")
        let double = try #require(try await repo.all(userId: user).first)
        #expect(WorkoutRootView.destination(of: double) == .routine(id: double.id))
    }

    @Test func dayTitleAndLengthFollowTheDay() async throws {
        let repo = SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: { Date() })
        let user = UUID()
        let routine = try await repo.create(name: "Push · Mon", notes: nil, userId: user)
        try await repo.addDay(routineId: routine.id, name: "Push")
        let loaded = try #require(try await repo.all(userId: user).first)
        let day = loaded.days[0]
        #expect(RoutineDayView.title(of: day, routine: loaded) == "Push · Mon")
        #expect(RoutineDayView.title(of: day, routine: nil) == "Push")
        #expect(RoutineDayView.estimatedMinutes(day) == 0)
        _ = try await repo.addExercise(
            dayId: day.id, ref: .catalog("bench"), input: RoutineExerciseInput(targetSets: 4, restSeconds: 75))
        let filled = try #require(try await repo.all(userId: user).first?.days.first)
        #expect(RoutineDayView.estimatedMinutes(filled) == 8)  // 4 × (45 + 75) s
    }
}
