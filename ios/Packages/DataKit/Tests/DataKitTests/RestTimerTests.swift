@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite struct RestDefaultsTests {
    @Test func programRestWinsThenMechanicThenFallback() {
        #expect(RestDefaults.seconds(program: 150, mechanic: "isolation") == 150)
        #expect(RestDefaults.seconds(program: nil, mechanic: "compound") == 120)
        #expect(RestDefaults.seconds(program: nil, mechanic: "Isolation") == 75)
        #expect(RestDefaults.seconds(program: 0, mechanic: "compound") == 120)
        #expect(RestDefaults.seconds(program: nil, mechanic: nil) == 90)
        #expect(RestDefaults.seconds(program: nil, mechanic: "other") == 90)
    }
}

@MainActor
@Suite struct RestTimerControllerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // swiftlint:disable:next large_tuple
    private func make(status: NotificationAuthorization = .authorized, grants: Bool = true) -> (
        RestTimerController, TestClock, FakeNotificationService, UserDefaults
    ) {
        let clock = TestClock(t0)
        let service = FakeNotificationService(status: status, grantsOnRequest: grants)
        let defaults = UserDefaults(suiteName: "rest-timer-\(UUID().uuidString)")!
        let controller = RestTimerController(
            clock: clock.closure, notifications: service, defaults: defaults,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        return (controller, clock, service, defaults)
    }

    @Test func remainingFollowsTheClock() async {
        let (timer, clock, _, _) = make()
        await timer.start(seconds: 90, title: "t", body: "b")
        #expect(timer.isRunning && timer.remaining() == 90)
        clock.advance(by: 30)
        #expect(timer.remaining() == 60)
        #expect(abs(timer.fraction() - 60.0 / 90.0) < 1e-9)
    }

    @Test func adjustAddsAndRemovesFifteenSeconds() async {
        let (timer, clock, _, _) = make()
        await timer.start(seconds: 60, title: "t", body: "b")
        await timer.adjust(by: 15)
        #expect(timer.remaining() == 75 && timer.run?.total == 75)
        clock.advance(by: 10)
        await timer.adjust(by: -15)
        #expect(timer.remaining() == 50 && timer.run?.total == 60)
    }

    @Test func removingMoreThanLeftEndsTheTimerQuietly() async {
        let (timer, clock, service, _) = make()
        await timer.start(seconds: 60, title: "t", body: "b")
        clock.advance(by: 50)
        await timer.adjust(by: -15)
        #expect(!timer.isRunning && timer.finishCount == 0)
        #expect(await service.scheduled.isEmpty)
    }

    @Test func skipStopsAndCancelsTheNotification() async {
        let (timer, _, service, _) = make()
        await timer.start(seconds: 60, title: "t", body: "b")
        await timer.scenePhaseChanged(active: false)
        #expect(await service.scheduled.count == 1)
        await timer.skip()
        #expect(!timer.isRunning && timer.remaining() == 0)
        #expect(await service.scheduled.isEmpty)
    }

    @Test func backgroundSchedulesAtTheEndMomentAndForegroundCancels() async {
        let (timer, clock, service, _) = make()
        await timer.start(seconds: 90, title: "Rest over", body: "Next set")
        clock.advance(by: 20)
        await timer.scenePhaseChanged(active: false)
        let pending = await service.scheduled[RestTimerController.notificationId]
        #expect(pending == LocalNotification(
            id: RestTimerController.notificationId, title: "Rest over", body: "Next set", fireDate: t0.addingTimeInterval(90)
        ))
        clock.advance(by: 30)
        await timer.scenePhaseChanged(active: true)
        #expect(await service.scheduled.isEmpty)
        #expect(timer.isRunning && timer.remaining() == 40)
    }

    @Test func timerThatEndedInTheBackgroundIsClearedOnReturn() async {
        let (timer, clock, service, _) = make()
        await timer.start(seconds: 30, title: "t", body: "b")
        await timer.scenePhaseChanged(active: false)
        clock.advance(by: 120)
        await timer.scenePhaseChanged(active: true)
        #expect(!timer.isRunning && timer.finishCount == 0)
        #expect(await service.scheduled.isEmpty)
    }

    @Test func adjustWhileInBackgroundReschedules() async {
        let (timer, _, service, _) = make()
        await timer.start(seconds: 60, title: "t", body: "b")
        await timer.scenePhaseChanged(active: false)
        await timer.adjust(by: 15)
        #expect(await service.scheduled[RestTimerController.notificationId]?.fireDate == t0.addingTimeInterval(75))
    }

    @Test func finishingInTheForegroundCountsOnceAndFiresTheCue() async {
        let (timer, clock, _, _) = make()
        var cues = 0
        timer.onFinished = { cues += 1 }
        await timer.start(seconds: 10, title: "t", body: "b")
        await timer.finishIfDue()
        #expect(timer.isRunning && cues == 0)
        clock.advance(by: 10)
        await timer.finishIfDue()
        await timer.finishIfDue()
        #expect(!timer.isRunning && timer.finishCount == 1 && cues == 1)
    }

    @Test func noNotificationWithoutPermission() async {
        let (timer, _, service, _) = make(status: .denied)
        await timer.start(seconds: 60, title: "t", body: "b")
        await timer.scenePhaseChanged(active: false)
        #expect(await service.scheduled.isEmpty)
        #expect(!timer.showsPermissionPrimer)
    }

    @Test func primerShowsOnceBeforeTheSystemPrompt() async {
        let (timer, _, service, _) = make(status: .notDetermined)
        await timer.start(seconds: 60, title: "t", body: "b")
        #expect(timer.showsPermissionPrimer)
        #expect(await service.requestCount == 0)
        await timer.acceptPrimer()
        #expect(!timer.showsPermissionPrimer)
        #expect(await service.requestCount == 1)
        await timer.skip()
        await timer.start(seconds: 60, title: "t", body: "b")
        #expect(!timer.showsPermissionPrimer)
    }

    @Test func decliningThePrimerNeverTouchesTheSystemPromptAndIsNotAskedAgain() async {
        let (timer, _, service, defaults) = make(status: .notDetermined)
        await timer.start(seconds: 60, title: "t", body: "b")
        timer.declinePrimer()
        #expect(defaults.bool(forKey: RestTimerController.primerSeenKey))
        await timer.start(seconds: 60, title: "t", body: "b")
        #expect(!timer.showsPermissionPrimer)
        #expect(await service.requestCount == 0)
    }

    @Test func zeroSecondsDoesNotStart() async {
        let (timer, _, _, _) = make()
        await timer.start(seconds: 0, title: "t", body: "b")
        #expect(!timer.isRunning)
    }
}

@MainActor
@Suite struct ProgramRestTests {
    @Test func sessionKeepsRoutineRestPerExerciseAndRestoresIt() async throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let container = try DataStore.inMemory()
        let clock = TestClock(t0)
        let workouts = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let routines = SwiftDataRoutineRepository(modelContainer: container, clock: clock.closure)
        let bench = ExerciseRef.catalog("barbell_bench_press")
        let fly = ExerciseRef.catalog("cable_fly")
        let routine = try await routines.create(name: "Push", notes: nil, userId: testUser)
        let day = try await routines.addDay(routineId: routine.id, name: "Day")
        _ = try await routines.addExercise(dayId: day.id, ref: bench, input: RoutineExerciseInput(restSeconds: 180))
        _ = try await routines.addExercise(dayId: day.id, ref: fly, input: RoutineExerciseInput())

        let session = WorkoutSession(userId: testUser, workouts: workouts, routines: routines, clock: clock.closure)
        try await session.start(routineId: routine.id, dayId: day.id)
        let ids = try #require(session.workout).exercises.map(\.id)
        #expect(session.programRest[ids[0]] == 180)
        #expect(session.programRest[ids[1]] == .some(nil) || session.programRest[ids[1]] == nil)

        let again = WorkoutSession(userId: testUser, workouts: workouts, routines: routines, clock: clock.closure)
        #expect(try await again.restore())
        #expect(again.programRest[ids[0]] == 180)
    }
}
