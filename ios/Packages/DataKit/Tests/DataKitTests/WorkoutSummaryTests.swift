@testable import DataKit
import Foundation
import SwiftData
import Testing

private let bench = ExerciseRef.catalog("barbell_bench_press")
private let row = ExerciseRef.catalog("barbell_row")

private func snapshot(
    id: UUID = UUID(), start: Date, minutes: Double = 60, name: String? = nil, dayId: UUID? = nil,
    exercises: [(ExerciseRef, [SetInput])]
) -> WorkoutSnapshot {
    WorkoutSnapshot(
        id: id, userId: testUser, name: name, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
        routineId: nil, routineDayId: dayId, notes: nil, source: .manual, rating: nil, healthKitUUID: nil,
        createdAt: start, updatedAt: start, syncState: .pending,
        exercises: exercises.enumerated().map { index, entry in
            let exerciseId = UUID()
            return WorkoutExerciseSnapshot(
                id: exerciseId, workoutId: id, position: index, ref: entry.0, supersetGroup: nil, notes: nil,
                sets: entry.1.enumerated().map { SetSnapshot(id: UUID(), workoutExerciseId: exerciseId, position: $0, input: $1) }
            )
        }
    )
}

private func done(_ kg: Double, _ reps: Int, _ type: SetType = .working) -> SetInput {
    SetInput(weightKg: kg, reps: reps, setType: type, isCompleted: true)
}

@Suite struct WorkoutSummaryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func volumeCountsCompletedWorkingSetsOnly() {
        let workout = snapshot(start: t0, exercises: [
            (bench, [done(60, 10, .warmup), done(100, 5), done(100, 5), SetInput(weightKg: 100, reps: 5)]),
            (row, [done(80, 8)]),
        ])
        let summary = WorkoutSummary(workout: workout)
        #expect(summary.totalVolumeKg == 100 * 5 * 2 + 80 * 8)
        #expect(summary.setCount == 3)
        #expect(summary.exerciseCount == 2)
        #expect(summary.duration == 3600)
        #expect(summary.comparison == nil)
    }

    @Test func muscleLoadWeightsPrimaryAndSecondarySets() {
        let workout = snapshot(start: t0, exercises: [(bench, [done(100, 5), done(100, 5)]), (row, [done(80, 8)])])
        let muscles: [ExerciseRef: ExerciseMuscles] = [
            bench: ExerciseMuscles(primary: ["chest"], secondary: ["triceps", "shoulders"]),
            row: ExerciseMuscles(primary: ["lats"], secondary: ["biceps", "triceps"]),
        ]
        let load = WorkoutSummary(workout: workout, muscles: muscles).muscleLoad
        #expect(load["chest"] == 2)
        #expect(load["lats"] == 1)
        #expect(load["triceps"] == 1.5)  // 2 × 0.5 + 1 × 0.5
        #expect(load["biceps"] == 0.5)
        #expect(load["shoulders"] == 1)
    }

    @Test func aMuscleInBothListsCountsAsPrimaryOnly() {
        let workout = snapshot(start: t0, exercises: [(bench, [done(100, 5)])])
        let muscles = [bench: ExerciseMuscles(primary: ["chest"], secondary: ["chest"])]
        #expect(WorkoutSummary(workout: workout, muscles: muscles).muscleLoad == ["chest": 1])
    }

    @Test func exercisesWithoutCompletedSetsAddNoLoad() {
        let workout = snapshot(start: t0, exercises: [(bench, [SetInput(weightKg: 100, reps: 5)])])
        let muscles = [bench: ExerciseMuscles(primary: ["chest"])]
        let summary = WorkoutSummary(workout: workout, muscles: muscles)
        #expect(summary.muscleLoad.isEmpty)
        #expect(summary.exerciseCount == 0)
    }

    @Test func comparisonShowsVolumeSetAndDurationChange() {
        let earlier = snapshot(start: t0, minutes: 50, exercises: [(bench, [done(100, 5), done(100, 5)])])
        let later = snapshot(start: t0.addingTimeInterval(86_400), minutes: 60, exercises: [(bench, [done(100, 6), done(100, 6), done(100, 6)])])
        let comparison = WorkoutSummary(workout: later, previous: earlier).comparison
        #expect(comparison?.volumeDeltaKg == 800.0)
        #expect(comparison?.volumePercent == 80)
        #expect(comparison?.setDelta == 1)
        #expect(comparison?.durationDelta == 600)
        #expect(comparison?.previousDate == t0)
    }

    @Test func comparisonPercentIsNilWhenThePreviousVolumeWasZero() {
        let earlier = snapshot(start: t0, exercises: [(bench, [done(0, 10)])])
        let later = snapshot(start: t0.addingTimeInterval(86_400), exercises: [(bench, [done(50, 10)])])
        #expect(WorkoutSummary(workout: later, previous: earlier).comparison?.volumePercent == nil)
    }

    @Test func recordsKeepOneHitPerExerciseAndKindAndSkipUnconfirmed() {
        let first = PersonalRecordHit(ref: bench, kind: .weight, value: 100, setId: UUID())
        let second = PersonalRecordHit(ref: bench, kind: .weight, value: 105, setId: UUID())
        let held = PersonalRecordHit(ref: bench, kind: .e1rm, value: 200, setId: UUID(), needsConfirmation: true)
        let workout = snapshot(start: t0, exercises: [(bench, [done(100, 5)])])
        let records = WorkoutSummary(workout: workout, records: [first, second, held]).records
        #expect(records == [second])
    }

    // MARK: Previous comparable

    @Test func previousComparablePrefersTheSameRoutineDay() {
        let day = UUID()
        let sameDay = snapshot(start: t0, dayId: day, exercises: [(row, [done(50, 5)])])
        let sameExercises = snapshot(start: t0.addingTimeInterval(86_400), exercises: [(bench, [done(50, 5)])])
        let current = snapshot(start: t0.addingTimeInterval(2 * 86_400), dayId: day, exercises: [(bench, [done(50, 5)])])
        #expect(WorkoutSummary.previousComparable(to: current, among: [sameDay, sameExercises])?.id == sameDay.id)
    }

    @Test func previousComparableFallsBackToNameThenOverlap() {
        let named = snapshot(start: t0, name: "Push", exercises: [(row, [done(50, 5)])])
        let other = snapshot(start: t0.addingTimeInterval(86_400), name: "Pull", exercises: [(bench, [done(50, 5)])])
        let current = snapshot(start: t0.addingTimeInterval(2 * 86_400), name: "push", exercises: [(bench, [done(50, 5)])])
        #expect(WorkoutSummary.previousComparable(to: current, among: [named, other])?.id == named.id)
        let unnamed = snapshot(start: t0.addingTimeInterval(2 * 86_400), exercises: [(bench, [done(50, 5)])])
        #expect(WorkoutSummary.previousComparable(to: unnamed, among: [named, other])?.id == other.id)
    }

    @Test func previousComparableIgnoresLaterUnrelatedAndSelf() {
        let current = snapshot(start: t0, exercises: [(bench, [done(50, 5)])])
        let later = snapshot(start: t0.addingTimeInterval(86_400), exercises: [(bench, [done(50, 5)])])
        let unrelated = snapshot(start: t0.addingTimeInterval(-86_400), exercises: [(row, [done(50, 5)])])
        #expect(WorkoutSummary.previousComparable(to: current, among: [current, later, unrelated]) == nil)
    }

    // MARK: Finish assessment

    @Test func assessmentCountsOpenSetsAndFlagsShortOrEmptyWorkouts() {
        let open = SetInput(weightKg: 50, reps: 5)
        let workout = snapshot(start: t0, exercises: [(bench, [done(50, 5), open, open])])
        let long = FinishAssessment(workout: workout, now: t0.addingTimeInterval(1800))
        #expect(long.completedSets == 1)
        #expect(long.incompleteSets == 2)
        #expect(long.hasOpenSets)
        #expect(!long.needsSaveConfirmation)
        let short = FinishAssessment(workout: workout, now: t0.addingTimeInterval(90))
        #expect(short.isShort && short.needsSaveConfirmation)
        let empty = snapshot(start: t0, exercises: [(bench, [open])])
        let assessment = FinishAssessment(workout: empty, now: t0.addingTimeInterval(3600))
        #expect(assessment.isEmpty && assessment.needsSaveConfirmation)
    }
}

// MARK: - Repository and Health

private actor FakeHealth: HealthWorkoutWriting {
    private(set) var saved: [UUID: UUID] = [:]  // app workout id -> health uuid
    private(set) var deleted: [UUID] = []
    var available = true

    func setAvailable(_ value: Bool) { available = value }

    func saveWorkout(id: UUID, start: Date, end: Date) async -> UUID? {
        guard available else { return nil }
        if let existing = saved[id] { return existing }
        let uuid = UUID()
        saved[id] = uuid
        return uuid
    }

    func deleteWorkout(uuid: UUID) async -> Bool {
        deleted.append(uuid)
        saved = saved.filter { $0.value != uuid }
        return true
    }
}

@Suite struct WorkoutHealthTests {
    private func finishedWorkout(_ repo: SwiftDataWorkoutRepository, clock: TestClock) async throws -> UUID {
        let started = try await repo.start(WorkoutDraft(startedAt: clock.now, exercises: [
            WorkoutExerciseDraft(ref: bench, sets: [done(100, 5)]),
        ]), userId: testUser)
        clock.advance(by: 3600)
        return try await repo.finish(id: started.id, at: clock.now).id
    }

    @Test func ratingAndHealthUUIDAreStoredAndValidated() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let id = try await finishedWorkout(repo, clock: clock)
        try await repo.setRating(id: id, rating: 4)
        let uuid = UUID()
        try await repo.setHealthKitUUID(id: id, uuid: uuid)
        let stored = try #require(try await repo.workout(id: id))
        #expect(stored.rating == 4 && stored.healthKitUUID == uuid)
        await #expect(throws: DataError.self) { try await repo.setRating(id: id, rating: 6) }
        await #expect(throws: DataError.self) { try await repo.setRating(id: id, rating: 0) }
        try await repo.setRating(id: id, rating: nil)
        #expect(try await repo.workout(id: id)?.rating == nil)
    }

    @Test func recorderWritesOnceAndStoresTheUUID() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let health = FakeHealth()
        let recorder = WorkoutHealthRecorder(workouts: repo, health: health)
        let id = try await finishedWorkout(repo, clock: clock)
        let first = await recorder.record(workoutId: id)
        let second = await recorder.record(workoutId: id)
        #expect(first != nil && first == second)
        #expect(try await repo.workout(id: id)?.healthKitUUID == first)
        #expect(await health.saved.count == 1)
    }

    @Test func recorderSkipsActiveWorkoutsAndUnavailableHealth() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let health = FakeHealth()
        let recorder = WorkoutHealthRecorder(workouts: repo, health: health)
        let active = try await repo.start(WorkoutDraft(startedAt: clock.now), userId: testUser)
        #expect(await recorder.record(workoutId: active.id) == nil)
        try await repo.delete(id: active.id)
        let id = try await finishedWorkout(repo, clock: clock)
        await health.setAvailable(false)
        #expect(await recorder.record(workoutId: id) == nil)
        #expect(try await repo.workout(id: id)?.healthKitUUID == nil)
        await health.setAvailable(true)
        #expect(await recorder.record(workoutId: id) != nil)
    }

    @Test func removingDeletesTheHealthRecordAndAllowsRewriting() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let health = FakeHealth()
        let recorder = WorkoutHealthRecorder(workouts: repo, health: health)
        let id = try await finishedWorkout(repo, clock: clock)
        let uuid = try #require(await recorder.record(workoutId: id))
        await recorder.remove(workoutId: id)
        #expect(await health.deleted == [uuid])
        #expect(try await repo.workout(id: id)?.healthKitUUID == nil)
        #expect(await recorder.record(workoutId: id) != nil)
    }
}

@Suite struct WorkoutRestoreTests {
    @Test func restoreBringsBackOnlyWhatDeletedWithTheWorkout() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let started = try await repo.start(WorkoutDraft(startedAt: clock.now, exercises: [
            WorkoutExerciseDraft(ref: bench, sets: [done(100, 5), done(90, 5)]),
        ]), userId: testUser)
        let setIds = started.exercises[0].sets.map(\.id)
        clock.advance(by: 60)
        try await repo.removeSet(id: setIds[1])  // removed earlier, must stay removed
        clock.advance(by: 60)
        try await repo.finish(id: started.id, at: clock.now)
        clock.advance(by: 60)
        try await repo.delete(id: started.id)
        #expect(try await repo.workout(id: started.id) == nil)
        clock.advance(by: 60)
        try await repo.restore(id: started.id)
        let back = try #require(try await repo.workout(id: started.id))
        #expect(back.exercises.count == 1)
        #expect(back.exercises[0].sets.map(\.id) == [setIds[0]])
        #expect(back.positionsAreContiguous)
        try await repo.restore(id: started.id)  // not deleted: no-op
    }

    @Test func finishedWorkoutsPageNewestFirstAndSkipDeletedAndActive() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        var ids: [UUID] = []
        for index in 0..<5 {
            let started = try await repo.start(WorkoutDraft(
                startedAt: clock.now, exercises: [WorkoutExerciseDraft(ref: bench, sets: [done(100, 5 + index)])]
            ), userId: testUser)
            clock.advance(by: 1800)
            try await repo.finish(id: started.id, at: clock.now)
            ids.append(started.id)
            clock.advance(by: 86_400)
        }
        try await repo.delete(id: ids[2])
        _ = try await repo.start(WorkoutDraft(startedAt: clock.now), userId: testUser)
        let firstPage = try await repo.finishedWorkouts(userId: testUser, before: nil, limit: 2)
        #expect(firstPage.map(\.id) == [ids[4], ids[3]])
        let secondPage = try await repo.finishedWorkouts(userId: testUser, before: firstPage.last?.startedAt, limit: 2)
        #expect(secondPage.map(\.id) == [ids[1], ids[0]])
        #expect(try await repo.finishedDates(userId: testUser).count == 4)
        #expect(try await repo.finishedWorkouts(userId: otherUser, before: nil, limit: 5).isEmpty)
    }
}

