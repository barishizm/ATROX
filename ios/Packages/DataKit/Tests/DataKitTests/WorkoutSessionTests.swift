@testable import DataKit
import Foundation
import SwiftData
import Testing

private let bench = ExerciseRef.catalog("barbell_bench_press")
private let squat = ExerciseRef.catalog("barbell_squat")
private let row = ExerciseRef.catalog("barbell_row")

private func done(_ kg: Double, _ reps: Int, type: SetType = .working) -> SetInput {
    SetInput(weightKg: kg, reps: reps, setType: type, isCompleted: true)
}

@Suite struct WorkoutPrefillTests {
    @Test func noTargetRepeatsLastTimeOrPlansThreeEmptySets() {
        #expect(WorkoutPrefill.sets(target: nil, last: []) == Array(repeating: SetInput(), count: 3))
        let last = [done(40, 10, type: .warmup), done(80, 8)]
        let planned = WorkoutPrefill.sets(target: nil, last: last)
        #expect(planned.map(\.weightKg) == [40, 80])
        #expect(planned.map(\.setType) == [.warmup, .working])
        #expect(planned.allSatisfy { !$0.isCompleted })
    }

    @Test func targetSetsTakeLastWorkingValuesByIndex() {
        let target = RoutineExerciseInput(targetSets: 4, targetRepsMin: 6, targetRepsMax: 8, targetRir: 2)
        let last = [done(40, 10, type: .warmup), done(80, 8), done(82.5, 6)]
        let planned = WorkoutPrefill.sets(target: target, last: last)
        #expect(planned.count == 4)
        #expect(planned.map(\.weightKg) == [80, 82.5, 82.5, 82.5])
        #expect(planned.map(\.reps) == [8, 6, 6, 6])
        #expect(planned.allSatisfy { $0.rir == 2 && $0.setType == .working && !$0.isCompleted })
    }

    @Test func targetWithoutHistoryUsesTopOfRepRange() {
        let planned = WorkoutPrefill.sets(target: RoutineExerciseInput(targetSets: 2, targetRepsMin: 8, targetRepsMax: 12), last: [])
        #expect(planned == Array(repeating: SetInput(weightKg: 0, reps: 12), count: 2))
    }

    @Test func nextSetCopiesTheLastOneUncompleted() {
        #expect(WorkoutPrefill.nextSet(after: []) == SetInput())
        #expect(WorkoutPrefill.nextSet(after: [done(60, 5)]) == SetInput(weightKg: 60, reps: 5))
        #expect(WorkoutPrefill.nextSet(after: [done(20, 10, type: .warmup)]).setType == .working)
    }
}

@MainActor
@Suite struct WorkoutSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Env {
        let container: ModelContainer
        let clock: TestClock
        let workouts: SwiftDataWorkoutRepository
        let routines: SwiftDataRoutineRepository

        @MainActor
        func session(records: (any PersonalRecordDetecting)? = nil) -> WorkoutSession {
            WorkoutSession(userId: testUser, workouts: workouts, routines: routines, records: records, clock: clock.closure)
        }
    }

    private func makeEnv() throws -> Env {
        let container = try DataStore.inMemory()
        let clock = TestClock(t0)
        return Env(
            container: container, clock: clock,
            workouts: SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure),
            routines: SwiftDataRoutineRepository(modelContainer: container, clock: clock.closure)
        )
    }

    /// Records a finished session of `ref` an hour before the test start.
    private func seedHistory(_ env: Env, _ ref: ExerciseRef, _ sets: [SetInput]) async throws {
        let start = t0.addingTimeInterval(-7200)
        _ = try await env.workouts.start(
            WorkoutDraft(
                startedAt: start, endedAt: start.addingTimeInterval(3600),
                exercises: [WorkoutExerciseDraft(ref: ref, sets: sets)]
            ),
            userId: testUser
        )
    }

    private func collect(_ stream: AsyncStream<WorkoutEvent>, count: Int) async -> [WorkoutEvent] {
        var result: [WorkoutEvent] = []
        for await event in stream {
            result.append(event)
            if result.count == count { break }
        }
        return result
    }

    // MARK: Start

    @Test func emptyStartIsActiveAndSyncLocked() async throws {
        let env = try makeEnv()
        let session = env.session()
        #expect(session.phase == .idle)
        try await session.startEmpty()
        #expect(session.phase == .active)
        #expect(session.workout?.exercises.isEmpty == true)
        #expect(session.workout?.isSyncLocked == true)
        #expect(session.workout?.source == .manual)
        await #expect(throws: WorkoutSessionError.alreadyActive) { try await session.startEmpty() }
    }

    @Test func startFromRoutineDayPrefillsTargetsAndLastTime() async throws {
        let env = try makeEnv()
        try await seedHistory(env, bench, [done(80, 8), done(80, 7)])
        let routine = try await env.routines.create(name: "PPL", notes: nil, userId: testUser)
        let day = try await env.routines.addDay(routineId: routine.id, name: "Push")
        _ = try await env.routines.addExercise(
            dayId: day.id, ref: bench, input: RoutineExerciseInput(targetSets: 3, targetRepsMin: 6, targetRepsMax: 8, targetRir: 1)
        )
        _ = try await env.routines.addExercise(dayId: day.id, ref: squat, input: RoutineExerciseInput(targetSets: 2, targetRepsMax: 5))

        let session = env.session()
        try await session.start(routineId: routine.id, dayId: day.id)
        let workout = try #require(session.workout)
        #expect(workout.name == "Push" && workout.source == .routine && workout.routineDayId == day.id)
        #expect(workout.exercises.map(\.ref) == [bench, squat])
        #expect(workout.exercises[0].sets.map(\.input.weightKg) == [80, 80, 80])
        #expect(workout.exercises[0].sets.map(\.input.reps) == [8, 7, 7])
        #expect(workout.exercises[0].sets.allSatisfy { $0.input.rir == 1 && !$0.input.isCompleted })
        #expect(workout.exercises[1].sets.map(\.input.reps) == [5, 5])
        #expect(session.previous[workout.exercises[0].id] == [done(80, 8), done(80, 7)])
        #expect(session.previous[workout.exercises[1].id] == [])
    }

    @Test func unknownRoutineDayIsRejected() async throws {
        let env = try makeEnv()
        let session = env.session()
        await #expect(throws: WorkoutSessionError.unknownRoutineDay) { try await session.start(routineId: UUID(), dayId: UUID()) }
        #expect(session.phase == .idle)
    }

    // MARK: Sets

    @Test func completeAndUndoSetAreStoredImmediately() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let setId = try #require(session.exercise(exerciseId)?.sets.first?.id)
        try await session.setWeight(setId, kg: 100)
        try await session.setReps(setId, reps: 5)
        try await session.setRir(setId, rir: 2)
        try await session.completeSet(setId)

        let stored = try #require(try await env.workouts.workout(id: session.workout!.id))
        #expect(stored.exercises[0].sets[0].input == SetInput(weightKg: 100, reps: 5, rir: 2, isCompleted: true))
        try await session.uncompleteSet(setId)
        #expect(try await env.workouts.workout(id: stored.id)?.exercises[0].sets[0].input.isCompleted == false)
    }

    @Test func invalidValuesThrowAndChangeNothing() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let setId = try #require(session.exercise(exerciseId)?.sets.first?.id)
        await #expect(throws: DataError.invalidValue("weightKg")) { try await session.setWeight(setId, kg: -5) }
        await #expect(throws: DataError.invalidValue("reps")) { try await session.setReps(setId, reps: 500) }
        #expect(session.set(setId)?.input == SetInput())
        await #expect(throws: WorkoutSessionError.unknownSet) { try await session.completeSet(UUID()) }
    }

    @Test func addRemoveAndRetypeSets() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let first = try #require(session.exercise(exerciseId)?.sets.first?.id)
        try await session.setWeight(first, kg: 60)
        try await session.setType(first, to: .warmup)
        #expect(session.set(first)?.input.setType == .warmup)

        let added = try await session.addSet(to: exerciseId)
        #expect(session.exercise(exerciseId)?.sets.count == 4)
        #expect(session.set(added)?.input.isCompleted == false)

        try await session.removeSet(first)
        let positions = session.exercise(exerciseId)?.sets.map(\.position)
        #expect(positions == [0, 1, 2])
        #expect(session.workout?.positionsAreContiguous == true)
    }

    @Test func removingTheLastSetKeepsTheExercise() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        for set in session.exercise(exerciseId)?.sets ?? [] { try await session.removeSet(set.id) }
        #expect(session.exercise(exerciseId)?.sets.isEmpty == true)
        // A set can be added back, starting from an empty set.
        let added = try await session.addSet(to: exerciseId)
        #expect(session.set(added)?.input == SetInput())
    }

    // MARK: Exercises

    @Test func addReplaceMoveAndRemoveExercises() async throws {
        let env = try makeEnv()
        try await seedHistory(env, row, [done(70, 10), done(70, 10)])
        let session = env.session()
        try await session.startEmpty()
        let benchId = try await session.addExercise(bench)
        let squatId = try await session.addExercise(squat)
        try await session.setExerciseNotes(squatId, notes: "  belt  ")
        #expect(session.exercise(squatId)?.notes == "belt")

        let rowId = try await session.replaceExercise(squatId, with: row)
        #expect(session.exercise(squatId) == nil)
        #expect(session.workout?.exercises.map(\.ref) == [bench, row])
        #expect(session.exercise(rowId)?.notes == "belt")
        #expect(session.exercise(rowId)?.sets.map(\.input.weightKg) == [70, 70])
        #expect(session.previous[rowId]?.count == 2)

        try await session.moveExercise(rowId, to: 0)
        #expect(session.workout?.exercises.map(\.ref) == [row, bench])
        try await session.removeExercise(benchId)
        #expect(session.workout?.exercises.map(\.ref) == [row])
        #expect(session.workout?.positionsAreContiguous == true)
        await #expect(throws: WorkoutSessionError.unknownExercise) { try await session.removeExercise(benchId) }
    }

    @Test func workoutNotesAreStored() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty(name: "Evening")
        try await session.setNotes("felt strong")
        #expect(try await env.workouts.workout(id: session.workout!.id)?.notes == "felt strong")
        try await session.setNotes("   ")
        #expect(session.workout?.notes == nil)
        #expect(session.workout?.name == "Evening")
    }

    // MARK: Time

    @Test func elapsedFollowsTheClockNotATimer() async throws {
        let env = try makeEnv()
        let session = env.session()
        #expect(session.elapsed() == 0)
        try await session.startEmpty()
        env.clock.advance(by: 754)
        #expect(session.elapsed() == 754)
        #expect(session.elapsed(at: t0.addingTimeInterval(-10)) == 0)
    }

    // MARK: Events

    @Test func eventsForSetExerciseAndFinish() async throws {
        let env = try makeEnv()
        let session = env.session()
        let stream = session.events()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let sets = try #require(session.exercise(exerciseId)?.sets)
        try await session.removeSet(sets[2].id)
        try await session.setReps(sets[0].id, reps: 5)
        try await session.setReps(sets[1].id, reps: 5)
        try await session.completeSet(sets[0].id)
        try await session.completeSet(sets[0].id) // already completed: no second event
        try await session.completeSet(sets[1].id)
        let result = try await session.finish()

        guard case .finished(let finished) = result else { Issue.record("expected finished"); return }
        let events = await collect(stream, count: 4)
        #expect(events == [
            .setCompleted(workoutExerciseId: exerciseId, setId: sets[0].id),
            .setCompleted(workoutExerciseId: exerciseId, setId: sets[1].id),
            .exerciseCompleted(workoutExerciseId: exerciseId),
            .workoutFinished(finished),
        ])
    }

    @Test func personalRecordsComeFromTheDetector() async throws {
        struct AlwaysRecord: PersonalRecordDetecting {
            func records(for set: SetSnapshot, ref: ExerciseRef, userId: UUID, workoutId: UUID) async throws -> [PersonalRecordHit] {
                [PersonalRecordHit(ref: ref, kind: .weight, value: set.input.weightKg, setId: set.id)]
            }
        }
        let env = try makeEnv()
        let session = env.session(records: AlwaysRecord())
        let stream = session.events()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        let setId = try #require(session.exercise(exerciseId)?.sets.first?.id)
        try await session.setWeight(setId, kg: 120)
        try await session.completeSet(setId)
        let events = await collect(stream, count: 2)
        #expect(events.last == .prAchieved(PersonalRecordHit(ref: bench, kind: .weight, value: 120, setId: setId)))
    }

    // MARK: End

    @Test func finishDropsIncompleteSetsAndEmptyExercises() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let benchId = try await session.addExercise(bench)
        _ = try await session.addExercise(squat)
        let first = try #require(session.exercise(benchId)?.sets.first?.id)
        try await session.setReps(first, reps: 8)
        try await session.completeSet(first)
        env.clock.advance(by: 3600)

        let result = try await session.finish()
        guard case .finished(let workout) = result else { Issue.record("expected finished"); return }
        #expect(workout.exercises.map(\.ref) == [bench])
        #expect(workout.exercises[0].sets.count == 1)
        #expect(workout.endedAt == t0.addingTimeInterval(3600))
        #expect(workout.isSyncLocked == false)
        #expect(session.phase == .finished(workout))
        #expect(session.workout == nil)
        #expect(try await env.workouts.activeWorkout(userId: testUser) == nil)
        await #expect(throws: WorkoutSessionError.notActive) { try await session.completeSet(first) }
    }

    @Test func finishCanKeepIncompleteSets() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let benchId = try await session.addExercise(bench)
        try await session.completeSet(try #require(session.exercise(benchId)?.sets.first?.id))
        guard case .finished(let workout) = try await session.finish(dropIncomplete: false) else {
            Issue.record("expected finished"); return
        }
        #expect(workout.exercises[0].sets.count == 3)
    }

    @Test func finishingAnEmptyWorkoutDiscardsIt() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        _ = try await session.addExercise(bench)
        let id = try #require(session.workout?.id)
        #expect(try await session.finish() == .discarded)
        #expect(session.phase == .discarded)
        #expect(try await env.workouts.workout(id: id) == nil)
        #expect(try await env.workouts.activeWorkout(userId: testUser) == nil)
        // The slot is free again.
        try await env.session().startEmpty()
    }

    @Test func cancelSoftDeletesEverything() async throws {
        let env = try makeEnv()
        let session = env.session()
        try await session.startEmpty()
        let exerciseId = try await session.addExercise(bench)
        try await session.completeSet(try #require(session.exercise(exerciseId)?.sets.first?.id))
        let id = try #require(session.workout?.id)
        try await session.cancel()
        #expect(session.phase == .cancelled)
        #expect(try await env.workouts.workout(id: id) == nil)
        await #expect(throws: WorkoutSessionError.notActive) { try await session.cancel() }
        await #expect(throws: WorkoutSessionError.notActive) { try await session.finish() }
    }

    // MARK: Recovery

    @Test func restoreAfterAppKillContinuesWhereItStopped() async throws {
        let env = try makeEnv()
        try await seedHistory(env, bench, [done(90, 5), done(90, 5)])
        let first = env.session()
        try await first.startEmpty()
        let exerciseId = try await first.addExercise(bench)
        let setId = try #require(first.exercise(exerciseId)?.sets.first?.id)
        try await first.completeSet(setId)
        env.clock.advance(by: 1200)

        // "Kill": a brand-new session and repository over the same store.
        let reopened = WorkoutSession(
            userId: testUser,
            workouts: SwiftDataWorkoutRepository(modelContainer: env.container, clock: env.clock.closure),
            clock: env.clock.closure
        )
        #expect(try await reopened.restore())
        #expect(reopened.phase == .active)
        #expect(reopened.workout?.id == first.workout?.id)
        #expect(reopened.set(setId)?.input.isCompleted == true)
        #expect(reopened.previous[exerciseId] == [done(90, 5), done(90, 5)])
        #expect(reopened.elapsed() == 1200)
        let next = try #require(reopened.exercise(exerciseId)?.sets[1].id)
        try await reopened.completeSet(next)
        #expect(reopened.exercise(exerciseId)?.sets.filter(\.input.isCompleted).count == 2)
    }

    @Test func restoreWithoutActiveWorkoutStaysIdle() async throws {
        let env = try makeEnv()
        try await seedHistory(env, bench, [done(90, 5)])
        let session = env.session()
        #expect(try await session.restore() == false)
        #expect(session.phase == .idle)
        await #expect(throws: WorkoutSessionError.notActive) { try await session.addExercise(bench) }
    }
}
