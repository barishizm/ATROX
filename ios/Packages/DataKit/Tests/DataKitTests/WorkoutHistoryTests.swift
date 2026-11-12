@testable import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

private let bench = ExerciseRef.catalog("barbell_bench_press")
private let squat = ExerciseRef.catalog("barbell_squat")

private func done(_ kg: Double, _ reps: Int, _ type: SetType = .working) -> SetInput {
    SetInput(weightKg: kg, reps: reps, setType: type, isCompleted: true)
}

private actor RecordingHealth: HealthWorkoutWriting {
    private(set) var live: [UUID: UUID] = [:]

    func saveWorkout(id: UUID, start: Date, end: Date) async -> UUID? {
        if let existing = live[id] { return existing }
        let uuid = UUID()
        live[id] = uuid
        return uuid
    }

    func deleteWorkout(uuid: UUID) async -> Bool {
        live = live.filter { $0.value != uuid }
        return true
    }
}

private struct Env {
    let container: ModelContainer
    let clock: TestClock
    let workouts: SwiftDataWorkoutRepository
    let records: SwiftDataPersonalRecordService
    let health = RecordingHealth()

    init() throws {
        container = try DataStore.inMemory()
        clock = TestClock()
        workouts = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        records = SwiftDataPersonalRecordService(modelContainer: container, clock: clock.closure)
    }

    var editor: WorkoutHistoryEditor {
        WorkoutHistoryEditor(
            userId: testUser, workouts: workouts, records: records,
            health: WorkoutHealthRecorder(workouts: workouts, health: health)
        )
    }

    /// Trains and finishes one workout of `(ref, sets)` through the real session (so records are detected), a day later.
    @MainActor @discardableResult
    func train(_ exercises: [(ExerciseRef, [SetInput])]) async throws -> WorkoutSnapshot {
        let session = WorkoutSession(userId: testUser, workouts: workouts, records: records, clock: clock.closure)
        try await session.startEmpty()
        for (ref, sets) in exercises {
            let exerciseId = try await session.addExercise(ref)
            var ids = try #require(session.exercise(exerciseId)?.sets.map(\.id))
            while ids.count < sets.count { ids.append(try await session.addSet(to: exerciseId)) }
            for (id, set) in zip(ids, sets) {
                try await session.setWeight(id, kg: set.weightKg)
                try await session.setReps(id, reps: set.reps)
                try await session.setType(id, to: set.setType)
                try await session.completeSet(id)
            }
            for id in ids.dropFirst(sets.count) { try await session.removeSet(id) }
        }
        clock.advance(by: 3600)
        guard case .finished(let workout) = try await session.finish() else { throw DataError.notFound }
        clock.advance(by: 86_400)
        return workout
    }

    func record(_ metric: RecordMetric, _ ref: ExerciseRef = bench) async throws -> Double? {
        try await records.current(userId: testUser, ref: ref).first { $0.metric == metric }?.value
    }
}

@MainActor @Suite struct WorkoutHistoryEditorTests {
    @Test func editingAFinishedSetRebuildsRecords() async throws {
        let env = try Env()
        try await env.train([(bench, [done(100, 5)])])
        let second = try await env.train([(bench, [done(110, 5)])])
        #expect(try await env.record(.weight) == 110)
        let setId = try #require(second.exercises.first?.sets.first?.id)
        try await env.editor.editSet(workoutId: second.id, setId: setId) { $0.weightKg = 90 }
        #expect(try await env.record(.weight) == 100)
        try await env.editor.editSet(workoutId: second.id, setId: setId) { $0.weightKg = 120 }
        #expect(try await env.record(.weight) == 120)
    }

    @Test func uncompletingOrRemovingASetDropsItsRecord() async throws {
        let env = try Env()
        try await env.train([(bench, [done(100, 5)])])
        let second = try await env.train([(bench, [done(110, 5), done(60, 10)])])
        let setId = try #require(second.exercises.first?.sets.first?.id)
        try await env.editor.editSet(workoutId: second.id, setId: setId) { $0.isCompleted = false }
        #expect(try await env.record(.weight) == 100)
        try await env.editor.editSet(workoutId: second.id, setId: setId) { $0.isCompleted = true }
        #expect(try await env.record(.weight) == 110)
        try await env.editor.removeSet(workoutId: second.id, setId: setId)
        #expect(try await env.record(.weight) == 100)
        let after = try #require(try await env.workouts.workout(id: second.id))
        #expect(after.positionsAreContiguous)
    }

    @Test func addedSetAndExerciseCountAsDoneAndFeedRecords() async throws {
        let env = try Env()
        let workout = try await env.train([(bench, [done(100, 5)])])
        let exerciseId = try #require(workout.exercises.first?.id)
        let added = try await env.editor.addSet(workoutId: workout.id, exerciseId: exerciseId)
        #expect(added.input.isCompleted && added.input.weightKg == 100 && added.input.reps == 5)
        try await env.editor.editSet(workoutId: workout.id, setId: added.id) { $0.weightKg = 105 }
        #expect(try await env.record(.weight) == 105)
        let row = try await env.editor.addExercise(workoutId: workout.id, ref: squat)
        #expect(row.sets.allSatisfy { $0.input.isCompleted })
        try await env.editor.removeExercise(workoutId: workout.id, exerciseId: row.id)
        let stored = try #require(try await env.workouts.workout(id: workout.id))
        #expect(stored.exercises.map(\.ref) == [bench])
        #expect(stored.positionsAreContiguous)
    }

    @Test func editsToWarmupsLeaveRecordsAlone() async throws {
        let env = try Env()
        let workout = try await env.train([(bench, [done(40, 10, .warmup), done(100, 5)])])
        let warmup = try #require(workout.exercises.first?.sets.first)
        try await env.editor.editSet(workoutId: workout.id, setId: warmup.id) { $0.weightKg = 200 }
        #expect(try await env.record(.weight) == 100)
    }

    @Test func deleteFallsBackToEarlierRecordsAndUndoRestoresThem() async throws {
        let env = try Env()
        try await env.train([(bench, [done(100, 5)])])
        let second = try await env.train([(bench, [done(110, 5)])])
        let health = WorkoutHealthRecorder(workouts: env.workouts, health: env.health)
        #expect(await health.record(workoutId: second.id) != nil)
        try await env.editor.delete(workoutId: second.id)
        #expect(try await env.workouts.workout(id: second.id) == nil)
        #expect(try await env.record(.weight) == 100)
        #expect(await env.health.live.isEmpty)
        try await env.editor.undoDelete(workoutId: second.id)
        #expect(try await env.workouts.workout(id: second.id)?.exercises.count == 1)
        #expect(try await env.record(.weight) == 110)
        #expect(await env.health.live[second.id] != nil)
    }

    @Test func deletingTheOnlyWorkoutClearsItsRecords() async throws {
        let env = try Env()
        let only = try await env.train([(bench, [done(100, 5)])])
        try await env.editor.delete(workoutId: only.id)
        #expect(try await env.record(.weight) == nil)
    }

    @Test func detailsAndRatingAreCleanedAndStored() async throws {
        let env = try Env()
        let workout = try await env.train([(bench, [done(100, 5)])])
        try await env.editor.updateDetails(workoutId: workout.id, name: "  Heavy  ", notes: "   ")
        try await env.editor.setRating(workoutId: workout.id, rating: 5)
        let stored = try #require(try await env.workouts.workout(id: workout.id))
        #expect(stored.name == "Heavy" && stored.notes == nil && stored.rating == 5)
    }

    @Test func unknownWorkoutOrSetThrows() async throws {
        let env = try Env()
        let workout = try await env.train([(bench, [done(100, 5)])])
        await #expect(throws: DataError.self) { try await env.editor.delete(workoutId: UUID()) }
        await #expect(throws: DataError.self) {
            try await env.editor.editSet(workoutId: workout.id, setId: UUID()) { $0.reps = 1 }
        }
    }
}

@MainActor @Suite struct WorkoutRepeatAndConvertTests {
    @Test func repeatingStartsAnUncompletedCopy() async throws {
        let env = try Env()
        let finished = try await env.train([(bench, [done(40, 10, .warmup), done(100, 5), done(100, 4)]), (squat, [done(140, 5)])])
        let session = WorkoutSession(userId: testUser, workouts: env.workouts, records: env.records, clock: env.clock.closure)
        try await session.startRepeating(finished)
        let active = try #require(session.workout)
        #expect(active.id != finished.id && active.isActive)
        #expect(active.exercises.map(\.ref) == [bench, squat])
        let sets = active.exercises[0].sets.map(\.input)
        #expect(sets.map(\.weightKg) == [40, 100, 100])
        #expect(sets.map(\.reps) == [10, 5, 4])
        #expect(sets.map(\.setType) == [.warmup, .working, .working])
        #expect(sets.allSatisfy { !$0.isCompleted })
        // Last time shows the finished workout's sets.
        let previous = session.previous[active.exercises[0].id]
        #expect(previous?.count == 3)
    }

    @Test func repeatingWhileAWorkoutRunsIsRefused() async throws {
        let env = try Env()
        let finished = try await env.train([(bench, [done(100, 5)])])
        let session = WorkoutSession(userId: testUser, workouts: env.workouts, clock: env.clock.closure)
        try await session.startEmpty()
        await #expect(throws: WorkoutSessionError.alreadyActive) { try await session.startRepeating(finished) }
    }

    @Test func convertingBuildsOneDayWithTargetsFromTheSets() async throws {
        let env = try Env()
        let finished = try await env.train([
            (bench, [done(40, 10, .warmup), done(100, 8), done(100, 6), done(100, 5)]), (squat, [done(140, 5)]),
        ])
        let routines = SwiftDataRoutineRepository(modelContainer: env.container, clock: env.clock.closure)
        let routine = try await RoutineConverter.convert(
            finished, name: "From history", dayName: "Day 1", userId: testUser, routines: routines
        )
        #expect(routine.name == "From history")
        #expect(routine.days.count == 1)
        let rows = try #require(routine.days.first?.exercises)
        #expect(rows.map(\.ref) == [bench, squat])
        #expect(rows[0].input.targetSets == 3)
        #expect(rows[0].input.targetRepsMin == 5 && rows[0].input.targetRepsMax == 8)
        #expect(rows[1].input.targetSets == 1)
    }

    @Test func targetsOfAnExerciseWithoutWorkingSetsAreTheDefaults() {
        let exercise = WorkoutExerciseSnapshot(
            id: UUID(), workoutId: UUID(), position: 0, ref: bench, supersetGroup: nil, notes: nil, sets: []
        )
        let targets = RoutineConverter.targets(of: exercise)
        #expect(targets.targetSets == 1 && targets.targetRepsMin == nil && targets.targetRepsMax == nil)
    }
}

@Suite struct HistoryMathTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func workout(_ start: Date, kg: Double, minutes: Double = 60, active: Bool = false) -> WorkoutSnapshot {
        let exerciseId = UUID()
        let id = UUID()
        return WorkoutSnapshot(
            id: id, userId: testUser, name: nil, startedAt: start, endedAt: active ? nil : start.addingTimeInterval(minutes * 60),
            routineId: nil, routineDayId: nil, notes: nil, source: .manual, rating: nil, healthKitUUID: nil,
            createdAt: start, updatedAt: start, syncState: .pending,
            exercises: [
                WorkoutExerciseSnapshot(
                    id: exerciseId, workoutId: id, position: 0, ref: bench, supersetGroup: nil, notes: nil,
                    sets: [SetSnapshot(id: UUID(), workoutExerciseId: exerciseId, position: 0, input: done(kg, 10))]
                ),
            ]
        )
    }

    @Test func monthSummaryTotalsOnlyThatMonthsFinishedWorkouts() {
        let all = [
            workout(date(2026, 3, 31), kg: 100), workout(date(2026, 4, 1, 0), kg: 50), workout(date(2026, 4, 1, 20), kg: 60, minutes: 30),
            workout(date(2026, 4, 30, 23), kg: 70), workout(date(2026, 5, 1, 0), kg: 80), workout(date(2026, 4, 10), kg: 90, active: true),
        ]
        let summary = HistoryMath.monthSummary(of: all, month: date(2026, 4, 15), calendar: calendar)
        #expect(summary.workoutCount == 3)
        #expect(summary.trainedDays == [1, 30])
        // 60 + 30 + 60 minutes and 500 + 600 + 700 kg; plain literals keep CI's type checker fast.
        let expectedDuration: TimeInterval = 9_000
        let expectedVolume: Double = 1_800
        #expect(summary.totalDuration == expectedDuration)
        #expect(summary.totalVolumeKg == expectedVolume)
    }

    @Test func trainedDaysUseOnlyStartDatesInTheMonth() {
        let dates = [date(2026, 2, 28, 23), date(2026, 3, 1, 0), date(2026, 3, 15), date(2026, 3, 15, 22), date(2026, 4, 1, 0)]
        #expect(HistoryMath.trainedDays(in: dates, month: date(2026, 3, 9), calendar: calendar) == [1, 15])
        #expect(HistoryMath.monthRange(containing: date(2026, 2, 10), calendar: calendar).upperBound == date(2026, 3, 1, 0))
    }

    @Test func progressIsOldestFirstAndIgnoresWarmups() {
        func session(_ day: Int, _ sets: [SetInput]) -> ExerciseSession {
            ExerciseSession(
                workoutId: UUID(), date: date(2026, 1, day),
                sets: sets.enumerated().map { SetSnapshot(id: UUID(), workoutExerciseId: UUID(), position: $0, input: $1) }
            )
        }
        let sessions = [  // newest first, as the repository returns them
            session(20, [done(100, 5), done(100, 5)]), session(10, [done(150, 10, .warmup), done(90, 5)]),
            session(5, [done(0, 8)]),
        ]
        let progress = HistoryMath.progress(of: sessions)
        // The bodyweight session (0 kg) is a point without an e1RM; the warm-up never counts.
        #expect(progress.points.map(\.date) == [date(2026, 1, 5), date(2026, 1, 10), date(2026, 1, 20)])
        #expect(progress.points[0].e1rmKg == nil)
        #expect(progress.points[1].bestWeightKg == 90)
        #expect(progress.points[1].volumeKg == 450)
        #expect(progress.points[2].volumeKg == 1000)
        #expect(progress.heaviest?.input.weightKg == 100)
        #expect(abs((progress.bestE1rmKg ?? 0) - 100 * (1 + 5.0 / 30)) < 1e-9)
        #expect(progress.lastDate == date(2026, 1, 20))
        #expect(progress.sessionCount == 3)
        #expect(HistoryMath.progress(of: []).points.isEmpty)
    }
}

@Suite struct LargeHistoryTests {
    /// 500 finished workouts (≈ 10 000 sets): the screens only ever read a page, a month and the date list.
    @Test func fiveHundredWorkoutsStayFast() async throws {
        let container = try DataStore.inMemory()
        let repo = SwiftDataWorkoutRepository(modelContainer: container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let drafts = TrainingFixtures.largeHistory(count: 500, now: now)
        #expect(drafts.count == 500)
        for draft in drafts { try await repo.start(draft, userId: testUser) }

        let clock = ContinuousClock()
        var page: [WorkoutSnapshot] = []
        let firstPage = try await clock.measure { page = try await repo.finishedWorkouts(userId: testUser, before: nil, limit: 30) }
        #expect(page.count == 30)
        #expect(firstPage < .seconds(1))

        var dates: [Date] = []
        let datesTime = try await clock.measure { dates = try await repo.finishedDates(userId: testUser) }
        #expect(dates.count == 500)
        #expect(datesTime < .seconds(1))

        let month = HistoryMath.monthRange(containing: now)
        var monthWorkouts: [WorkoutSnapshot] = []
        let monthTime = try await clock.measure {
            monthWorkouts = try await repo.workouts(userId: testUser, from: month.lowerBound, to: month.upperBound)
        }
        #expect(monthTime < .seconds(1))
        #expect(monthWorkouts.allSatisfy { month.contains($0.startedAt) })

        // Paging walks the whole history without gaps or repeats.
        var seen = Set<UUID>()
        var cursor: Date?
        while true {
            let next = try await repo.finishedWorkouts(userId: testUser, before: cursor, limit: 50)
            if next.isEmpty { break }
            for workout in next { #expect(seen.insert(workout.id).inserted) }
            cursor = next.last?.startedAt
        }
        #expect(seen.count == 500)

        let squatHistory = try await clock.measure {
            _ = try await repo.history(userId: testUser, ref: .catalog("barbell-squat"), limit: 500)
        }
        #expect(squatHistory < .seconds(3))
    }
}
