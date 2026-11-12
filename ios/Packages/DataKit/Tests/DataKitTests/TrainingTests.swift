@testable import DataKit
import Foundation
import SwiftData
import Testing

private let bench = ExerciseRef.catalog("barbell-bench-press-medium-grip")
private let squat = ExerciseRef.catalog("barbell-squat")

private func done(_ kg: Double, _ reps: Int, type: SetType = .working) -> SetInput {
    SetInput(weightKg: kg, reps: reps, setType: type, isCompleted: true)
}

@Suite struct RoutineRepositoryTests {
    private func makeRepo(_ clock: TestClock = TestClock()) throws -> SwiftDataRoutineRepository {
        SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func buildsARoutineWithOrderedDaysAndExercises() async throws {
        let repo = try makeRepo()
        let routine = try await repo.create(name: "  PPL ", notes: nil, userId: testUser)
        #expect(routine.name == "PPL" && routine.syncState == .pending)
        let push = try await repo.addDay(routineId: routine.id, name: "Push")
        let pull = try await repo.addDay(routineId: routine.id, name: "Pull")
        let positions: [Int] = [push.position, pull.position]
        #expect(positions == [0, 1])
        try await repo.addExercise(dayId: push.id, ref: bench, input: RoutineExerciseInput(targetRepsMin: 8, targetRepsMax: 12))
        try await repo.addExercise(dayId: push.id, ref: .custom(UUID()), input: RoutineExerciseInput())
        let loaded = try #require(try await repo.routine(id: routine.id))
        #expect(loaded.days.map(\.name) == ["Push", "Pull"])
        #expect(loaded.days[0].exercises.map(\.position) == [0, 1])
        #expect(loaded.days[0].exercises[0].input.targetRepsMax == 12)
        #expect(loaded.exerciseCount == 2 && loaded.positionsAreContiguous)
    }

    @Test func deletingAndMovingKeepPositionsGapFree() async throws {
        let repo = try makeRepo()
        let routine = try await repo.create(name: "R", notes: nil, userId: testUser)
        let days = try await ["A", "B", "C", "D"].asyncMap { try await repo.addDay(routineId: routine.id, name: $0) }
        try await repo.moveDay(id: days[3].id, to: 0)
        #expect(try await repo.routine(id: routine.id)?.days.map(\.name) == ["D", "A", "B", "C"])
        try await repo.deleteDay(id: days[0].id)
        let after = try #require(try await repo.routine(id: routine.id))
        #expect(after.days.map(\.name) == ["D", "B", "C"] && after.positionsAreContiguous)
        try await repo.moveDay(id: days[1].id, to: 99)  // clamped to the end
        #expect(try await repo.routine(id: routine.id)?.days.map(\.name) == ["D", "C", "B"])
    }

    @Test func exerciseReorderAndDeleteRenumber() async throws {
        let repo = try makeRepo()
        let routine = try await repo.create(name: "R", notes: nil, userId: testUser)
        let day = try await repo.addDay(routineId: routine.id, name: "Day")
        let ids = [bench, squat, .catalog("barbell-deadlift")]
        let rows = try await ids.asyncMap { try await repo.addExercise(dayId: day.id, ref: $0, input: RoutineExerciseInput()) }
        try await repo.moveExercise(id: rows[2].id, to: 0)
        try await repo.deleteExercise(id: rows[0].id)
        let loaded = try #require(try await repo.routine(id: routine.id)).days[0].exercises
        #expect(loaded.map(\.ref) == [.catalog("barbell-deadlift"), squat])
        #expect(loaded.map(\.position) == [0, 1])
    }

    @Test func deletingARoutineSoftDeletesTheWholeTree() async throws {
        let clock = TestClock()
        let container = try DataStore.inMemory()
        let repo = SwiftDataRoutineRepository(modelContainer: container, clock: clock.closure)
        let routine = try await repo.create(name: "R", notes: nil, userId: testUser)
        let day = try await repo.addDay(routineId: routine.id, name: "Day")
        try await repo.addExercise(dayId: day.id, ref: bench, input: RoutineExerciseInput())
        clock.advance(by: 60)
        try await repo.delete(id: routine.id)
        #expect(try await repo.routine(id: routine.id) == nil)
        #expect(try await repo.all(userId: testUser).isEmpty)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<RoutineExercise>())
        let days = try context.fetch(FetchDescriptor<RoutineDay>())
        #expect(rows.count == 1 && rows.allSatisfy { $0.deletedAt == clock.now && $0.syncState == .pending })
        #expect(days.count == 1 && days.allSatisfy { $0.deletedAt == clock.now })
    }

    @Test func rejectsValuesTheServerWouldReject() async throws {
        let repo = try makeRepo()
        await #expect(throws: DataError.invalidValue("name")) { try await repo.create(name: "  ", notes: nil, userId: testUser) }
        let routine = try await repo.create(name: "R", notes: nil, userId: testUser)
        let day = try await repo.addDay(routineId: routine.id, name: "Day")
        for bad in [
            RoutineExerciseInput(targetSets: 0), RoutineExerciseInput(targetSets: 51),
            RoutineExerciseInput(targetRepsMin: 12, targetRepsMax: 8), RoutineExerciseInput(targetRir: 11),
            RoutineExerciseInput(supersetGroup: 0), RoutineExerciseInput(restSeconds: 3601),
        ] {
            await #expect(throws: DataError.self) { try await repo.addExercise(dayId: day.id, ref: bench, input: bad) }
        }
        #expect(try await repo.routine(id: routine.id)?.exerciseCount == 0)
    }
}

@Suite struct WorkoutRepositoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRepo(_ clock: TestClock = TestClock()) throws -> SwiftDataWorkoutRepository {
        SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory(), clock: clock.closure)
    }

    @Test func atMostOneActiveWorkout() async throws {
        let repo = try makeRepo()
        let first = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        #expect(first.isActive && first.source == .manual)
        #expect(try await repo.activeWorkout(userId: testUser)?.id == first.id)
        await #expect(throws: DataError.activeWorkoutExists) { try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser) }
        // Another user is unaffected, and finished history can still be recorded.
        _ = try await repo.start(WorkoutDraft(startedAt: t0), userId: otherUser)
        _ = try await repo.start(WorkoutDraft(startedAt: t0, endedAt: t0.addingTimeInterval(3600)), userId: testUser)
        try await repo.finish(id: first.id, at: t0.addingTimeInterval(600))
        #expect(try await repo.activeWorkout(userId: testUser) == nil)
        _ = try await repo.start(WorkoutDraft(startedAt: t0.addingTimeInterval(900)), userId: testUser)
        await #expect(throws: DataError.alreadyFinished) { try await repo.finish(id: first.id, at: t0.addingTimeInterval(700)) }
    }

    @Test func discardingTheActiveWorkoutFreesTheSlot() async throws {
        let repo = try makeRepo()
        let first = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        try await repo.delete(id: first.id)
        #expect(try await repo.activeWorkout(userId: testUser) == nil)
        _ = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
    }

    @Test func finishingBeforeTheStartIsRejected() async throws {
        let repo = try makeRepo()
        let workout = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        await #expect(throws: DataError.invalidValue("endedAt")) { try await repo.finish(id: workout.id, at: t0.addingTimeInterval(-1)) }
        await #expect(throws: DataError.invalidValue("endedAt")) {
            try await repo.start(WorkoutDraft(startedAt: t0, endedAt: t0.addingTimeInterval(-5)), userId: otherUser)
        }
    }

    @Test func incompleteAndWarmupSetsDoNotCountForScore() async throws {
        let repo = try makeRepo()
        let draft = WorkoutDraft(
            startedAt: t0, endedAt: t0.addingTimeInterval(3000),
            exercises: [
                WorkoutExerciseDraft(ref: bench, sets: [
                    done(40, 10, type: .warmup), done(80, 5), SetInput(weightKg: 80, reps: 5, isCompleted: false),
                    done(80, 0), done(75, 6, type: .drop),
                ])
            ]
        )
        let saved = try await repo.start(draft, userId: testUser)
        #expect(saved.exercises[0].sets.count == 5)
        #expect(saved.scoringSets.map(\.input.weightKg) == [80, 75])
        #expect(saved.positionsAreContiguous)
    }

    @Test func setsAndExercisesStayContiguous() async throws {
        let repo = try makeRepo()
        let workout = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        let a = try await repo.addExercise(workoutId: workout.id, ref: bench, supersetGroup: nil)
        let b = try await repo.addExercise(workoutId: workout.id, ref: squat, supersetGroup: 1)
        let c = try await repo.addExercise(workoutId: workout.id, ref: .custom(UUID()), supersetGroup: 1)
        let sets = try await (0..<3).asyncMap { try await repo.addSet(workoutExerciseId: a.id, input: done(60 + Double($0), 8)) }
        try await repo.removeSet(id: sets[0].id)
        try await repo.updateSet(id: sets[1].id, with: done(70, 9))
        try await repo.moveExercise(id: c.id, to: 0)
        try await repo.removeExercise(id: b.id)
        let loaded = try #require(try await repo.workout(id: workout.id))
        #expect(loaded.exercises.map(\.position) == [0, 1])
        #expect(loaded.exercises[1].ref == bench)
        #expect(loaded.exercises[1].sets.map(\.position) == [0, 1])
        #expect(loaded.exercises[1].sets.map(\.input.weightKg) == [70, 62])
        #expect(loaded.positionsAreContiguous)
    }

    @Test func invalidSetsAreRejectedWithoutWritingAnything() async throws {
        let repo = try makeRepo()
        let draft = WorkoutDraft(
            startedAt: t0, endedAt: t0.addingTimeInterval(60),
            exercises: [WorkoutExerciseDraft(ref: bench, sets: [done(80, 5), SetInput(weightKg: 80, reps: 101)])]
        )
        await #expect(throws: DataError.invalidValue("reps")) { try await repo.start(draft, userId: testUser) }
        #expect(try await repo.workouts(userId: testUser, from: .distantPast, to: .distantFuture).isEmpty)
        let workout = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        let row = try await repo.addExercise(workoutId: workout.id, ref: bench, supersetGroup: nil)
        for bad in [SetInput(weightKg: -1), SetInput(weightKg: 1001), SetInput(rpe: 11), SetInput(rir: 11), SetInput(weightKg: .nan)] {
            await #expect(throws: DataError.self) { try await repo.addSet(workoutExerciseId: row.id, input: bad) }
        }
    }

    @Test func historyAndLastSetsUseFinishedSessionsNewestFirst() async throws {
        let repo = try makeRepo()
        let day = 86_400.0
        for (index, weight) in [60.0, 62.5, 65].enumerated() {
            let start = t0.addingTimeInterval(Double(index) * day)
            _ = try await repo.start(
                WorkoutDraft(
                    startedAt: start, endedAt: start.addingTimeInterval(3600),
                    exercises: [WorkoutExerciseDraft(ref: bench, sets: [done(weight, 8), done(weight, 7), SetInput(weightKg: 99, reps: 1)])]
                ),
                userId: testUser
            )
        }
        // An active workout and another exercise must not leak into the history.
        let active = try await repo.start(WorkoutDraft(startedAt: t0.addingTimeInterval(9 * day)), userId: testUser)
        let row = try await repo.addExercise(workoutId: active.id, ref: bench, supersetGroup: nil)
        try await repo.addSet(workoutExerciseId: row.id, input: done(100, 1))
        _ = try await repo.start(
            WorkoutDraft(startedAt: t0, endedAt: t0.addingTimeInterval(60), exercises: [WorkoutExerciseDraft(ref: squat, sets: [done(100, 5)])]),
            userId: testUser
        )
        let history = try await repo.history(userId: testUser, ref: bench, limit: 10)
        #expect(history.map { $0.sets[0].input.weightKg } == [65, 62.5, 60])
        #expect(history.allSatisfy { $0.sets.count == 2 })
        #expect(try await repo.history(userId: testUser, ref: bench, limit: 2).count == 2)
        #expect(try await repo.lastSets(userId: testUser, ref: bench).map(\.input.weightKg) == [65, 65])
        #expect(try await repo.lastSets(userId: testUser, ref: .catalog("nope")).isEmpty)
        #expect(try await repo.lastSets(userId: otherUser, ref: bench).isEmpty)
    }

    @Test func dateRangeQueryIsHalfOpenAndNewestFirst() async throws {
        let repo = try makeRepo()
        let day = 86_400.0
        for index in 0..<5 {
            let start = t0.addingTimeInterval(Double(index) * day)
            _ = try await repo.start(WorkoutDraft(name: "W\(index)", startedAt: start, endedAt: start.addingTimeInterval(60)), userId: testUser)
        }
        let found = try await repo.workouts(userId: testUser, from: t0.addingTimeInterval(day), to: t0.addingTimeInterval(4 * day))
        #expect(found.map(\.name) == ["W3", "W2", "W1"])
    }

    @Test func recentExercisesAreDistinctAndNewestFirst() async throws {
        let repo = try makeRepo()
        let day = 86_400.0
        let sessions: [[ExerciseRef]] = [[bench, squat], [squat, .catalog("barbell-deadlift")]]
        for (index, refs) in sessions.enumerated() {
            let start = t0.addingTimeInterval(Double(index) * day)
            _ = try await repo.start(
                WorkoutDraft(startedAt: start, endedAt: start.addingTimeInterval(60), exercises: refs.map { WorkoutExerciseDraft(ref: $0, sets: [done(50, 5)]) }),
                userId: testUser
            )
        }
        #expect(try await repo.recentExercises(userId: testUser, limit: 10) == [squat, .catalog("barbell-deadlift"), bench])
        #expect(try await repo.recentExercises(userId: testUser, limit: 2).count == 2)
    }

    @Test func deletingAWorkoutSoftDeletesExercisesAndSets() async throws {
        let clock = TestClock()
        let container = try DataStore.inMemory()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let saved = try await repo.start(
            WorkoutDraft(startedAt: t0, endedAt: t0.addingTimeInterval(60), exercises: [WorkoutExerciseDraft(ref: bench, sets: [done(60, 5), done(60, 5)])]),
            userId: testUser
        )
        clock.advance(by: 30)
        try await repo.delete(id: saved.id)
        #expect(try await repo.workout(id: saved.id) == nil)
        #expect(try await repo.history(userId: testUser, ref: bench, limit: 5).isEmpty)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<SetEntry>()).allSatisfy { $0.deletedAt == clock.now && $0.syncState == .pending })
        #expect(try context.fetch(FetchDescriptor<WorkoutExercise>()).allSatisfy { $0.deletedAt == clock.now })
        await #expect(throws: DataError.notFound) { try await repo.delete(id: saved.id) }
    }

    @Test func onboardingWorkoutIsReplacedNotDuplicated() async throws {
        let repo = try makeRepo()
        func draft(_ kg: Double) -> WorkoutDraft {
            WorkoutDraft(startedAt: t0, exercises: [WorkoutExerciseDraft(ref: bench, sets: [done(kg, 5)])])
        }
        try await repo.replaceOnboardingWorkout(draft(60), userId: testUser)
        try await repo.replaceOnboardingWorkout(draft(70), userId: testUser)
        let all = try await repo.workouts(userId: testUser, from: .distantPast, to: .distantFuture)
        #expect(all.count == 1 && all[0].source == .onboarding && !all[0].isActive)
        #expect(all[0].exercises[0].sets[0].input.weightKg == 70)
        // It does not occupy the active slot, and skipping everything removes it.
        _ = try await repo.start(WorkoutDraft(startedAt: t0), userId: testUser)
        try await repo.replaceOnboardingWorkout(nil, userId: testUser)
        #expect(try await repo.workouts(userId: testUser, from: .distantPast, to: .distantFuture).count == 1)
    }
}

@Suite struct TrainingFixturesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func historyIsDeterministicAndShaped() {
        let a = TrainingFixtures.twelveWeekHistory(now: now)
        #expect(a == TrainingFixtures.twelveWeekHistory(now: now))
        #expect(a.count == 48)
        #expect(zip(a, a.dropFirst()).allSatisfy { $0.startedAt < $1.startedAt })
        #expect(a.allSatisfy { ($0.endedAt ?? .distantPast) > $0.startedAt && $0.endedAt! < now })
    }

    @Test func seededDataIsConsistent() async throws {
        let container = try DataStore.inMemory()
        try await TrainingFixtures.seed(container, userId: testUser, now: now)
        let workouts = SwiftDataWorkoutRepository(modelContainer: container)
        let all = try await workouts.workouts(userId: testUser, from: .distantPast, to: .distantFuture)
        #expect(all.count == 48 && all.allSatisfy { !$0.isActive && $0.positionsAreContiguous })
        #expect(try await workouts.activeWorkout(userId: testUser) == nil)
        // No overlaps and every workout points at a day of the seeded routine.
        let ordered = all.sorted { $0.startedAt < $1.startedAt }
        #expect(zip(ordered, ordered.dropFirst()).allSatisfy { $0.endedAt! <= $1.startedAt })
        let routine = try #require(try await SwiftDataRoutineRepository(modelContainer: container).all(userId: testUser).first)
        #expect(routine.days.count == 4 && routine.positionsAreContiguous)
        let dayIds = Set(routine.days.map(\.id))
        #expect(all.allSatisfy { $0.routineId == routine.id && dayIds.contains($0.routineDayId ?? UUID()) })
        // Progressive overload: the bench press gets heavier, and unfinished sets never count.
        let history = try await workouts.history(userId: testUser, ref: bench, limit: 100)
        #expect(history.count == 12)
        let top = history.reversed().map { $0.sets.map(\.input.weightKg).max() ?? 0 }
        #expect(zip(top, top.dropFirst()).allSatisfy { $0 <= $1 } && top.last! > top.first!)
        #expect(all.flatMap(\.exercises).flatMap(\.sets).contains { !$0.input.isCompleted })
        #expect(all.allSatisfy { $0.scoringSets.allSatisfy { $0.input.isCompleted && $0.input.reps >= 1 } })
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
