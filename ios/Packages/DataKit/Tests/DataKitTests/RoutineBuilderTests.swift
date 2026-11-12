@testable import DataKit
import Foundation
import Testing

private let bench = ExerciseRef.catalog("bench")
private let fly = ExerciseRef.catalog("fly")
private let row = ExerciseRef.catalog("row")
private let curl = ExerciseRef.catalog("curl")

@Suite struct RoutineBuilderTests {
    private func makeRepo() throws -> SwiftDataRoutineRepository {
        SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: TestClock().closure)
    }

    /// One routine with a "Push" day holding bench, fly, row, curl (in that order).
    private func seeded(_ repo: SwiftDataRoutineRepository) async throws -> (RoutineSnapshot, [RoutineExerciseSnapshot]) {
        let routine = try await repo.create(name: "PPL", notes: "n", userId: testUser)
        let day = try await repo.addDay(routineId: routine.id, name: "Push")
        var exercises: [RoutineExerciseSnapshot] = []
        for ref in [bench, fly, row, curl] {
            exercises.append(try await repo.addExercise(dayId: day.id, ref: ref, input: RoutineExerciseInput(targetSets: 3)))
        }
        return (try #require(try await repo.routine(id: routine.id)), exercises)
    }

    private func groups(_ repo: SwiftDataRoutineRepository, _ id: UUID) async throws -> [Int?] {
        try #require(try await repo.routine(id: id)).days[0].exercises.map(\.input.supersetGroup)
    }

    @Test func supersetMovesMembersNextToEachOther() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[2].id])  // bench + row
        let day = try #require(try await repo.routine(id: routine.id)).days[0]
        #expect(day.exercises.map(\.ref) == [bench, row, fly, curl])
        let shared: [Int?] = day.exercises.map(\.input.supersetGroup)
        #expect(shared[0] != nil && shared[0] == shared[1] && shared[2] == nil && shared[3] == nil)
        #expect(day.exercises.map(\.position) == [0, 1, 2, 3])
    }

    @Test func supersetNeedsTwoExercisesOfOneDay() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        await #expect(throws: DataError.self) { try await repo.setSuperset(exerciseIds: [ex[0].id]) }
        let other = try await repo.addDay(routineId: routine.id, name: "Pull")
        let foreign = try await repo.addExercise(dayId: other.id, ref: curl, input: RoutineExerciseInput())
        await #expect(throws: DataError.self) { try await repo.setSuperset(exerciseIds: [ex[0].id, foreign.id]) }
    }

    @Test func threeWaySupersetAndLeavingIt() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[1].id, ex[2].id])
        let all = try await groups(repo, routine.id)
        #expect(all[0] != nil && all[0] == all[1] && all[1] == all[2] && all[3] == nil)
        try await repo.clearSuperset(exerciseId: ex[2].id)
        let two = try await groups(repo, routine.id)
        #expect(two[0] != nil && two[0] == two[1] && two[2] == nil)
        try await repo.clearSuperset(exerciseId: ex[1].id)  // a lone member dissolves
        let none = try await groups(repo, routine.id)
        #expect(none.allSatisfy { $0 == nil })
    }

    @Test func draggingOutOfASupersetBreaksOnlyThatLink() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[1].id, ex[2].id])
        try await repo.moveExercise(id: ex[0].id, to: 3)  // bench leaves: fly+row stay together
        let day = try #require(try await repo.routine(id: routine.id)).days[0]
        #expect(day.exercises.map(\.ref) == [fly, row, curl, bench])
        let flags: [Int?] = day.exercises.map(\.input.supersetGroup)
        #expect(flags[0] != nil && flags[0] == flags[1] && flags[2] == nil && flags[3] == nil)
    }

    @Test func deletingAMemberDissolvesAPair() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[1].id])
        try await repo.deleteExercise(id: ex[1].id)
        #expect(try await groups(repo, routine.id).allSatisfy { $0 == nil })
    }

    @Test func movingWithinAGroupKeepsItWhole() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        // A four-way group where the last member moves to the front stays one run of four.
        try await repo.setSuperset(exerciseIds: ex.map(\.id))
        try await repo.moveExercise(id: ex[3].id, to: 0)
        let flags = try await groups(repo, routine.id)
        #expect(flags.allSatisfy { $0 != nil && $0 == flags[0] })  // still one run of four
    }

    @Test func duplicatingAnExercisePutsTheCopyBehindIt() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[1].id])
        let copy = try await repo.duplicateExercise(id: ex[0].id)
        let day = try #require(try await repo.routine(id: routine.id)).days[0]
        #expect(copy.id != ex[0].id)
        #expect(day.exercises.map(\.ref) == [bench, bench, fly, row, curl])
        #expect(day.exercises[1].id == copy.id && day.exercises[1].input.supersetGroup == nil)
        #expect(day.exercises.map(\.position) == [0, 1, 2, 3, 4])
    }

    @Test func duplicatingADayCopiesItsExercisesBehindIt() async throws {
        let repo = try makeRepo()
        let (routine, ex) = try await seeded(repo)
        let pull = try await repo.addDay(routineId: routine.id, name: "Pull")
        try await repo.setSuperset(exerciseIds: [ex[0].id, ex[1].id])
        let copy = try await repo.duplicateDay(id: routine.days[0].id, name: "Push 2")
        let loaded = try #require(try await repo.routine(id: routine.id))
        #expect(loaded.days.map(\.name) == ["Push", "Push 2", "Pull"])
        #expect(loaded.days[2].id == pull.id && loaded.positionsAreContiguous)
        #expect(copy.exercises.map(\.ref) == [bench, fly, row, curl])
        #expect(Set(copy.exercises.map(\.id)).isDisjoint(with: Set(ex.map(\.id))))
        #expect(copy.exercises[0].input.supersetGroup != nil)
    }

    @Test func duplicatingARoutineCopiesEverythingWithNewIds() async throws {
        let repo = try makeRepo()
        let (routine, _) = try await seeded(repo)
        let copy = try await repo.duplicate(routineId: routine.id, name: "PPL copy")
        #expect(copy.id != routine.id && copy.name == "PPL copy" && copy.notes == "n")
        #expect(copy.days.count == 1 && copy.exerciseCount == 4 && copy.positionsAreContiguous)
        #expect(copy.days[0].id != routine.days[0].id)
        #expect(try await repo.all(userId: testUser).count == 2)
    }

    @Test func restoreUndoesDeletesRenamesAndAdditions() async throws {
        let repo = try makeRepo()
        let (before, ex) = try await seeded(repo)
        try await repo.update(id: before.id, name: "Changed", notes: nil)
        try await repo.deleteExercise(id: ex[1].id)
        try await repo.deleteDay(id: before.days[0].id)
        let extra = try await repo.addDay(routineId: before.id, name: "New")
        try await repo.addExercise(dayId: extra.id, ref: curl, input: RoutineExerciseInput())

        try await repo.restore(before)
        let after = try #require(try await repo.routine(id: before.id))
        #expect(after.name == before.name && after.notes == before.notes)
        #expect(after.days.map(\.id) == before.days.map(\.id))
        #expect(after.days[0].exercises.map(\.id) == before.days[0].exercises.map(\.id))
        #expect(after.days[0].exercises.map(\.input) == before.days[0].exercises.map(\.input))
        #expect(after.positionsAreContiguous)
    }

    @Test func restoreBringsBackADeletedRoutine() async throws {
        let repo = try makeRepo()
        let (before, _) = try await seeded(repo)
        try await repo.delete(id: before.id)
        #expect(try await repo.routine(id: before.id) == nil)
        try await repo.restore(before)
        #expect(try await repo.routine(id: before.id)?.exerciseCount == 4)
    }
}

@Suite struct RoutineVolumeTests {
    private func routine(_ days: [[(ExerciseRef, Int)]]) async throws -> RoutineSnapshot {
        let repo = SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: TestClock().closure)
        let built = try await repo.create(name: "R", notes: nil, userId: testUser)
        for (index, exercises) in days.enumerated() {
            let day = try await repo.addDay(routineId: built.id, name: "D\(index)")
            for (ref, sets) in exercises {
                try await repo.addExercise(dayId: day.id, ref: ref, input: RoutineExerciseInput(targetSets: sets))
            }
        }
        return try #require(try await repo.routine(id: built.id))
    }

    private let lookup: RoutineVolume.MuscleLookup = { ref in
        switch ref {
        case bench: (["chest"], ["triceps", "shoulders"])
        case fly: (["chest"], [])
        case row: (["lats"], ["biceps"])
        default: nil
        }
    }

    @Test func sumsPrimaryFullAndSecondaryHalfAcrossDays() async throws {
        let built = try await routine([[(bench, 4), (fly, 3)], [(row, 4), (bench, 2)]])
        let counts = Dictionary(uniqueKeysWithValues: RoutineVolume.weeklySets(in: built, muscles: lookup).map { ($0.muscle, $0.sets) })
        #expect(counts["chest"] == 9 && counts["lats"] == 4)
        #expect(counts["triceps"] == 3 && counts["shoulders"] == 3 && counts["biceps"] == 2)
    }

    @Test func orderedByVolumeAndSkipsUnknownExercises() async throws {
        let built = try await routine([[(curl, 5), (row, 4), (fly, 6)]])
        let result = RoutineVolume.weeklySets(in: built, muscles: lookup)
        #expect(result.map(\.muscle) == ["chest", "lats", "biceps"])
    }

    @Test func secondaryDoesNotDoubleCountAPrimaryMuscle() async throws {
        let built = try await routine([[(bench, 4)]])
        let overlapping: RoutineVolume.MuscleLookup = { _ in (["chest"], ["chest", "triceps"]) }
        let sets = RoutineVolume.weeklySets(in: built, muscles: overlapping)
        let counts = Dictionary(uniqueKeysWithValues: sets.map { ($0.muscle, $0.sets) })
        #expect(counts["chest"] == 4 && counts["triceps"] == 2)
    }

    @Test func findsEmptyDays() async throws {
        let built = try await routine([[(bench, 3)], [], [(row, 3)]])
        #expect(RoutineVolume.emptyDays(in: built).map(\.name) == ["D1"])
    }
}

@MainActor
@Suite struct RoutinePlanStoreTests {
    private func defaults() -> UserDefaults {
        let suite = "plan-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test func persistsActiveRoutineAndWeekdaysPerUser() {
        let suite = defaults()
        let routine = UUID(), day = UUID()
        let store = RoutinePlanStore(userId: testUser, defaults: suite)
        store.setActive(routine)
        store.assign(dayId: day, toWeekday: 2)
        store.assign(dayId: day, toWeekday: 4)
        let again = RoutinePlanStore(userId: testUser, defaults: suite)
        #expect(again.activeRoutineId == routine && again.weekdays(of: day) == [2, 4])
        let other = RoutinePlanStore(userId: otherUser, defaults: suite)
        #expect(other.activeRoutineId == nil && other.dayByWeekday.isEmpty)
    }

    @Test func assigningNilFreesTheWeekdayAndBadWeekdaysAreIgnored() {
        let store = RoutinePlanStore(userId: testUser, defaults: defaults())
        store.assign(dayId: UUID(), toWeekday: 3)
        store.assign(dayId: nil, toWeekday: 3)
        store.assign(dayId: UUID(), toWeekday: 9)
        #expect(store.dayByWeekday[3] == nil && store.dayByWeekday.isEmpty)
    }

    @Test func pruneDropsGoneDaysAndGoneActiveRoutine() {
        let keepDay = UUID(), goneDay = UUID(), routine = UUID()
        let store = RoutinePlanStore(userId: testUser, defaults: defaults())
        store.assign(dayId: keepDay, toWeekday: 1)
        store.assign(dayId: goneDay, toWeekday: 2)
        store.setActive(routine)
        store.prune(validDayIds: [keepDay], validRoutineIds: [])
        #expect(store.dayByWeekday == [1: keepDay] && store.activeRoutineId == nil)
    }
}
