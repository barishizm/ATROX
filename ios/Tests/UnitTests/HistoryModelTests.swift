import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

@testable import ATROX

@MainActor
@Suite struct HistoryModelTests {
    private let user = UUID()
    private let bench = ExerciseRef.catalog("bench")

    @MainActor
    private struct Env {
        let context: HistoryContext
        let repo: SwiftDataWorkoutRepository
        let events = HistoryEvents()
    }

    private func makeEnv(unit: ATROX.WeightUnit = .kilograms) throws -> Env {
        let container = try DataStore.inMemory()
        let repo = SwiftDataWorkoutRepository(modelContainer: container)
        let records = SwiftDataPersonalRecordService(modelContainer: container)
        let context = HistoryContext(
            userId: user, workouts: repo, editor: WorkoutHistoryEditor(userId: user, workouts: repo, records: records),
            routines: SwiftDataRoutineRepository(modelContainer: container), records: records, unit: unit,
            locale: Locale(identifier: "en_US"), languageCode: "en", loadNames: { ["bench": "Bench Press"] }
        )
        return Env(context: context, repo: repo)
    }

    /// `count` finished bench workouts, one per day ending yesterday; returns them oldest first.
    @discardableResult
    private func seed(_ env: Env, count: Int, kg: @Sendable (Int) -> Double = { 60 + Double($0) }) async throws -> [WorkoutSnapshot] {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400 * Double(count))
        var result: [WorkoutSnapshot] = []
        for index in 0..<count {
            let start = day.addingTimeInterval(86_400 * Double(index) + 3600 * 10)
            let draft = WorkoutDraft(
                startedAt: start, endedAt: start.addingTimeInterval(3600),
                exercises: [WorkoutExerciseDraft(ref: bench, sets: [SetInput(weightKg: kg(index), reps: 5, isCompleted: true)])]
            )
            let started = try await env.repo.start(draft, userId: user)
            result.append(started)
            try await env.context.records.exerciseChanged(ref: bench, userId: user)
        }
        return result
    }

    @Test func listPagesNewestFirstWithoutGaps() async throws {
        let env = try makeEnv()
        let seeded = try await seed(env, count: 70)
        let model = HistoryModel(context: env.context, events: env.events)
        await model.load()
        #expect(model.workouts.count == HistoryModel.pageSize)
        #expect(model.workouts.first?.id == seeded.last?.id)
        #expect(model.hasMore)
        await model.loadMoreIfNeeded(current: model.workouts[3])  // not the last row: nothing happens
        #expect(model.workouts.count == 30)
        await model.loadMoreIfNeeded(current: model.workouts[29])
        #expect(model.workouts.count == 60)
        await model.loadMoreIfNeeded(current: model.workouts[59])
        #expect(model.workouts.count == 70)
        #expect(!model.hasMore)
        #expect(Set(model.workouts.map(\.id)).count == 70)
    }

    @Test func monthShowsTotalsAndMarksTrainedDays() async throws {
        let env = try makeEnv()
        try await seed(env, count: 3)
        let model = HistoryModel(context: env.context, events: env.events)
        await model.load()
        let thisMonth = HistoryMath.monthRange(containing: Date())
        let expected = model.workouts.filter { thisMonth.contains($0.startedAt) }
        #expect(model.monthSummary.workoutCount == expected.count)
        #expect(model.monthSummary.trainedDays.count <= 3)
        #expect(!model.canShowNextMonth)
        await model.shiftMonth(by: -1)
        await model.shiftMonth(by: 1)
        #expect(model.monthSummary.workoutCount == expected.count)
    }

    @Test func deleteHidesTheWorkoutAndUndoBringsItBack() async throws {
        let env = try makeEnv()
        let seeded = try await seed(env, count: 3)
        let model = HistoryModel(context: env.context, events: env.events)
        await model.load()
        let target = try #require(seeded.last)
        await model.delete(target, title: "Push")
        #expect(model.workouts.map(\.id).contains(target.id) == false)
        #expect(env.events.undo == HistoryEvents.PendingUndo(id: target.id, title: "Push"))
        #expect(env.events.version == 1)
        await model.undoDelete()
        #expect(model.workouts.first?.id == target.id)
        #expect(env.events.undo == nil)
    }

    @Test func detailEditsASetAndRebuildsRecords() async throws {
        let env = try makeEnv()
        let seeded = try await seed(env, count: 2, kg: { $0 == 0 ? 100 : 110 })
        let last = try #require(seeded.last)
        let model = WorkoutDetailModel(id: last.id, context: env.context, events: env.events)
        await model.load()
        let setId = try #require(model.workout?.exercises.first?.sets.first?.id)
        #expect(model.recordKinds[setId]?.first == .weight)
        #expect(await model.saveSet(setId, weightText: "90", repsText: "5", type: .working))
        #expect(model.workout?.exercises.first?.sets.first?.input.weightKg == 90)
        #expect(model.recordKinds[setId] == nil)  // the earlier 100 kg workout holds the record again
        let first = try #require(seeded.first?.exercises.first?.sets.first?.id)
        #expect(model.recordKinds[first] == nil)  // belongs to another workout, not shown here
        #expect(env.events.version == 1)
    }

    @Test func detailRejectsInvalidSetValuesWithoutWriting() async throws {
        let env = try makeEnv()
        let workout = try #require(try await seed(env, count: 1).first)
        let model = WorkoutDetailModel(id: workout.id, context: env.context, events: env.events)
        await model.load()
        let setId = try #require(model.workout?.exercises.first?.sets.first?.id)
        #expect(await model.saveSet(setId, weightText: "abc", repsText: "5", type: .working) == false)
        #expect(model.errorKey == "history.error.invalidSet")
        model.errorKey = nil
        #expect(await model.saveSet(setId, weightText: "50", repsText: "101", type: .working) == false)
        #expect(await model.saveSet(setId, weightText: "-5", repsText: "5", type: .working) == false)
        #expect(model.workout?.exercises.first?.sets.first?.input.weightKg == 60)
        #expect(env.events.version == 0)
    }

    @Test func detailUsesTheDisplayUnitForEditing() async throws {
        let env = try makeEnv(unit: .pounds)
        let workout = try #require(try await seed(env, count: 1, kg: { _ in 100 }).first)
        let model = WorkoutDetailModel(id: workout.id, context: env.context, events: env.events)
        await model.load()
        #expect(model.editableWeight(100) == "220.46")
        let setId = try #require(model.workout?.exercises.first?.sets.first?.id)
        #expect(await model.saveSet(setId, weightText: "225", repsText: "5", type: .warmup))
        let stored = try #require(model.workout?.exercises.first?.sets.first?.input)
        #expect(abs(stored.weightKg - 102.058) < 0.001)
        #expect(stored.setType == .warmup)
    }

    @Test func detailDeleteClosesAndOffersUndo() async throws {
        let env = try makeEnv()
        let workout = try #require(try await seed(env, count: 1).first)
        let model = WorkoutDetailModel(id: workout.id, context: env.context, events: env.events)
        await model.load()
        await model.delete(title: "Legs")
        #expect(model.wasDeleted)
        #expect(env.events.undo?.id == workout.id)
        #expect(try await env.repo.workout(id: workout.id) == nil)
    }

    @Test func detailConvertsToAProgram() async throws {
        let env = try makeEnv()
        let workout = try #require(try await seed(env, count: 1).first)
        let model = WorkoutDetailModel(id: workout.id, context: env.context, events: env.events)
        await model.load()
        #expect(await model.convertToRoutine(name: "From history", dayName: "Day 1"))
        let routines = try await env.context.routines.all(userId: user)
        #expect(routines.map(\.name) == ["From history"])
        #expect(routines.first?.days.first?.exercises.first?.input.targetRepsMin == 5)
    }

    @Test func exerciseHistoryBuildsChartPointsInTheDisplayUnit() async throws {
        let env = try makeEnv(unit: .pounds)
        try await seed(env, count: 3, kg: { 100 + Double($0) * 10 })
        let model = ExerciseHistoryModel(ref: bench, context: env.context)
        await model.load()
        #expect(model.name == "Bench Press")
        #expect(model.progress.sessionCount == 3)
        #expect(model.chartPoints.count == 3)
        #expect(model.chartPoints.map(\.date) == model.chartPoints.map(\.date).sorted())
        let firstKg = try #require(E1RMModel.standard.estimate(weightKg: 100, reps: 5)?.valueKg)
        #expect(abs(model.chartPoints[0].value - firstKg * 2.2046226) < 0.01)
        #expect(model.heaviestText == "88 lb × 5" || model.heaviestText?.hasSuffix("lb × 5") == true)
        #expect(model.recordText(.weight) != nil)
        #expect(model.sessions.count == 3)
    }

    @Test func exerciseHistoryOfAnUntrainedExerciseIsEmpty() async throws {
        let env = try makeEnv()
        let model = ExerciseHistoryModel(ref: .catalog("never-done"), context: env.context)
        await model.load()
        #expect(model.isEmpty && model.chartPoints.isEmpty && model.heaviestText == nil)
        #expect(!model.failed)
    }

    @Test func fiveHundredWorkoutsLoadTheFirstPageQuickly() async throws {
        let env = try makeEnv()
        let drafts = TrainingFixtures.largeHistory(count: 500, now: Date())
        for draft in drafts { try await env.repo.start(draft, userId: user) }
        let model = HistoryModel(context: env.context, events: env.events)
        let clock = ContinuousClock()
        let elapsed = await clock.measure { await model.load() }
        #expect(model.workouts.count == HistoryModel.pageSize)
        #expect(elapsed < .seconds(2))
    }
}
