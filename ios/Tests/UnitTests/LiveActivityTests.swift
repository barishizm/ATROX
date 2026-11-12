import DataKit
import Foundation
import Testing

@testable import ATROX

@MainActor
private struct Fixture {
    let session: WorkoutSession
    let rest: RestTimerController
    let service: FakeLiveActivityService
    let coordinator: LiveActivityCoordinator
    let bench: UUID
    let fly: UUID
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static let names: [String: String] = ["bench": "Bench Press", "fly": "Cable Fly"]

    init(enabled: Bool = true, preference: Bool = true, started: Bool = true) async throws {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: UUID(), workouts: repo)
        if started { try await session.startEmpty(name: "Push day") }
        let bench = started ? try await session.addExercise(.catalog("bench")) : UUID()
        let fly = started ? try await session.addExercise(.catalog("fly")) : UUID()
        if started { // 2 sets each keeps the numbers easy to follow
            for id in [bench, fly] {
                while (session.exercise(id)?.sets.count ?? 0) > 2, let last = session.exercise(id)?.sets.last {
                    try await session.removeSet(last.id)
                }
            }
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let rest = RestTimerController(clock: { t0 }, notifications: FakeNotificationService(status: .authorized))
        let service = FakeLiveActivityService(enabled: enabled)
        self.session = session
        self.rest = rest
        self.service = service
        self.bench = bench
        self.fly = fly
        self.coordinator = LiveActivityCoordinator(
            session: session, rest: rest, service: service, fallbackName: "Workout",
            exerciseName: { ref in
                if case .catalog(let id) = ref { Self.names[id] ?? "?" } else { "?" }
            },
            isEnabled: { preference }, clock: { t0 }
        )
    }

    func setIds(_ exercise: UUID) -> [UUID] { session.exercise(exercise)?.sets.map(\.id) ?? [] }

    var upserts: [WorkoutActivityAttributes.ContentState] {
        service.calls.compactMap { if case .upsert(let state) = $0 { state } else { nil } }
    }
}

@MainActor
@Suite struct WorkoutActivityMapperTests {
    @Test func showsTheFirstOpenSetOfTheFirstUnfinishedExercise() async throws {
        let f = try await Fixture()
        let workout = try #require(f.session.workout)
        var state = WorkoutActivityMapper.state(workout: workout, rest: nil, now: f.t0) { _ in "Bench Press" }
        #expect(state.exerciseName == "Bench Press")
        #expect(state.setNumber == 1 && state.setCount == 2)
        #expect(state.completedSets == 0 && state.totalSets == 4)

        try await f.session.completeSet(f.setIds(f.bench)[0])
        state = WorkoutActivityMapper.state(
            workout: try #require(f.session.workout), rest: nil, now: f.t0
        ) { _ in "Bench Press" }
        #expect(state.setNumber == 2 && state.setCount == 2, "Bench Press · 2/2")
        #expect(state.completedSets == 1)
    }

    @Test func movesOnToTheNextExerciseAndStaysOnTheLastWhenEverythingIsDone() async throws {
        let f = try await Fixture()
        for id in f.setIds(f.bench) { try await f.session.completeSet(id) }
        var workout = try #require(f.session.workout)
        var state = WorkoutActivityMapper.state(workout: workout, rest: nil, now: f.t0) { ref in
            ref == .catalog("fly") ? "Cable Fly" : "Bench Press"
        }
        #expect(state.exerciseName == "Cable Fly" && state.setNumber == 1)

        for id in f.setIds(f.fly) { try await f.session.completeSet(id) }
        workout = try #require(f.session.workout)
        state = WorkoutActivityMapper.state(workout: workout, rest: nil, now: f.t0) { _ in "Cable Fly" }
        #expect(state.exerciseName == "Cable Fly")
        #expect(state.setNumber == 2 && state.setCount == 2, "never past the last set")
        #expect(state.completedSets == 4 && state.totalSets == 4)
    }

    @Test func restWindowIsOnlyIncludedWhileItIsRunning() async throws {
        let f = try await Fixture()
        let workout = try #require(f.session.workout)
        let run = RestTimerController.Run(startedAt: f.t0, endsAt: f.t0.addingTimeInterval(90), total: 90)
        let resting = WorkoutActivityMapper.state(workout: workout, rest: run, now: f.t0.addingTimeInterval(10)) { _ in "x" }
        #expect(resting.restStart == f.t0 && resting.restEnd == f.t0.addingTimeInterval(90))
        #expect(WorkoutActivityMapper.staleDate(for: resting) == f.t0.addingTimeInterval(90), "stale when the rest runs out")

        let over = WorkoutActivityMapper.state(workout: workout, rest: run, now: f.t0.addingTimeInterval(91)) { _ in "x" }
        #expect(over.restStart == nil && over.restEnd == nil)
        #expect(WorkoutActivityMapper.staleDate(for: over) == nil)
    }

    @Test func finalStateDropsTheRestAndMarksTheEnd() async throws {
        let f = try await Fixture()
        let workout = try #require(f.session.workout)
        let run = RestTimerController.Run(startedAt: f.t0, endsAt: f.t0.addingTimeInterval(90), total: 90)
        let live = WorkoutActivityMapper.state(workout: workout, rest: run, now: f.t0) { _ in "x" }
        let final = WorkoutActivityMapper.finalState(of: live, endedAt: f.t0.addingTimeInterval(3000))
        #expect(final.isFinished && final.endedAt == f.t0.addingTimeInterval(3000))
        #expect(final.restStart == nil && final.restEnd == nil)
        #expect(final.exerciseName == live.exerciseName)
    }

    @Test func attributesUseTheWorkoutNameOrTheFallback() async throws {
        let f = try await Fixture()
        let workout = try #require(f.session.workout)
        let named = WorkoutActivityMapper.attributes(for: workout, fallbackName: "Workout")
        #expect(named.workoutName == "Push day" && named.workoutId == workout.id && named.startedAt == workout.startedAt)

        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let unnamed = WorkoutSession(userId: UUID(), workouts: repo)
        try await unnamed.startEmpty()
        let snapshot = try #require(unnamed.workout)
        let name = WorkoutActivityMapper.attributes(for: snapshot, fallbackName: "Workout").workoutName
        #expect(name == (snapshot.name?.isEmpty == false ? snapshot.name : "Workout"))
    }
}

@MainActor
@Suite struct LiveActivityCoordinatorTests {
    @Test func startingWithAnActiveWorkoutShowsItAndKeepsOnlyThatActivity() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        #expect(f.service.calls.first == .endAll(except: f.session.workout?.id))
        #expect(f.upserts.count == 1)
        #expect(f.upserts[0].exerciseName == "Bench Press" && f.upserts[0].setNumber == 1)
        #expect(f.service.attributes?.workoutId == f.session.workout?.id)
    }

    @Test func leftoverActivitiesAreEndedWhenNoWorkoutIsActive() async throws {
        let f = try await Fixture(started: false)
        await f.coordinator.start()
        #expect(f.service.calls == [.endAll(except: nil)])
    }

    @Test func updatesOnlyWhenTheContentChanges() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        await f.coordinator.requestSync()
        #expect(f.upserts.count == 1, "same content, no second update")

        try await f.session.completeSet(f.setIds(f.bench)[0])
        await f.coordinator.requestSync()
        #expect(f.upserts.count == 2)
        #expect(f.upserts[1].setNumber == 2 && f.upserts[1].completedSets == 1)
    }

    @Test func restStartAndEndAreReflectedWithAStaleDate() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        await f.rest.start(seconds: 90, title: "t", body: "b")
        await f.coordinator.requestSync()
        let resting = try #require(f.upserts.last)
        #expect(resting.restEnd == f.t0.addingTimeInterval(90))
        #expect(f.service.staleDate == f.t0.addingTimeInterval(90))

        await f.rest.skip()
        await f.coordinator.requestSync()
        #expect(f.upserts.last?.restEnd == nil)
        #expect(f.service.staleDate == nil)
    }

    @Test func finishingEndsWithASummary() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        let id = try #require(f.session.workout?.id)
        for set in f.setIds(f.bench) { try await f.session.completeSet(set) }
        _ = try await f.session.finish()
        await f.coordinator.requestSync()
        #expect(f.service.calls.last == .end(id, summary: true))
    }

    @Test func cancellingEndsWithoutASummary() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        let id = try #require(f.session.workout?.id)
        try await f.session.cancel()
        await f.coordinator.requestSync()
        #expect(f.service.calls.last == .end(id, summary: false))
    }

    @Test func nothingIsStartedWhenTheUserTurnedItOffOrTheSystemDoesNotAllowIt() async throws {
        let off = try await Fixture(preference: false)
        await off.coordinator.start()
        #expect(off.upserts.isEmpty)

        let denied = try await Fixture(enabled: false)
        await denied.coordinator.start()
        #expect(denied.upserts.isEmpty)
    }

    @Test func turningItOffMidWorkoutEndsTheActivityAndBackOnRestartsIt() async throws {
        let repo = SwiftDataWorkoutRepository(modelContainer: try DataStore.inMemory())
        let session = WorkoutSession(userId: UUID(), workouts: repo)
        try await session.startEmpty()
        _ = try await session.addExercise(.catalog("bench"))
        let service = FakeLiveActivityService()
        var allowed = true
        let coordinator = LiveActivityCoordinator(
            session: session, rest: RestTimerController(notifications: FakeNotificationService(status: .denied)),
            service: service, fallbackName: "Workout", exerciseName: { _ in "Bench Press" }, isEnabled: { allowed }
        )
        await coordinator.start()
        let id = try #require(session.workout?.id)
        allowed = false
        await coordinator.preferenceChanged()
        #expect(service.calls.last == .end(id, summary: false))
        allowed = true
        await coordinator.preferenceChanged()
        if case .upsert = service.calls.last {} else { Issue.record("expected the activity to start again") }
    }

    @Test func followsChangesWithoutBeingAsked() async throws {
        let f = try await Fixture()
        await f.coordinator.start()
        try await f.session.completeSet(f.setIds(f.bench)[0])
        for _ in 0..<200 where f.upserts.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(f.upserts.count == 2)
    }
}

@MainActor
@Suite struct RestCommandCenterTests {
    @Test func commandsReachTheHandler() async {
        var received: [RestCommand] = []
        RestCommandCenter.shared.handler = { received.append($0) }
        await RestCommandCenter.shared.send(.skip)
        await RestCommandCenter.shared.send(.adjust(seconds: 15))
        #expect(received == [.skip, .adjust(seconds: 15)])
        RestCommandCenter.shared.handler = nil
        await RestCommandCenter.shared.send(.skip)
        #expect(received.count == 2, "no handler: ignored")
    }
}
