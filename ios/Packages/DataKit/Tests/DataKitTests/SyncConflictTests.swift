@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite("Sync conflicts, tombstones, failures, clock skew, lock (P044)")
struct SyncConflictTests {
    /// Server and devices share one clock unless a test skews it.
    let clock = TestClock()

    struct Pair {
        let server: InMemoryRemoteStore
        let deviceA: SyncDevice
        let deviceB: SyncDevice
        let row: BodyMeasurement
    }

    /// Two devices that both hold one synced measurement.
    private func setUp() async throws -> Pair {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let deviceA = try SyncDevice(server: server, clock: clock)
        let deviceB = try SyncDevice(server: server, clock: clock)
        let row = measurement(80, on: clock.now, now: clock.now)
        try deviceA.insert([row])
        try await deviceA.engine.sync()
        try await deviceB.engine.sync()
        return Pair(server: server, deviceA: deviceA, deviceB: deviceB, row: row)
    }

    @Test func newerRemoteEditReplacesOlderPendingEdit() async throws {
        let pair = try await setUp()
        let (deviceA, deviceB, row) = (pair.deviceA, pair.deviceB, pair.row)
        clock.advance(by: 10)
        try deviceB.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 79 }   // B edits first, stays offline
        clock.advance(by: 10)
        try deviceA.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 81 }
        try await deviceA.engine.sync()                                            // A's later edit reaches the server

        try await deviceB.engine.sync()

        let local = try #require(try deviceB.fetch(BodyMeasurement.self, id: row.id))
        #expect(local.weightKg == 81)
        #expect(local.syncState == .synced)
    }

    @Test func newerPendingEditSurvivesThePullAndWins() async throws {
        let pair = try await setUp()
        let (server, deviceA, deviceB, row) = (pair.server, pair.deviceA, pair.deviceB, pair.row)
        clock.advance(by: 10)
        try deviceA.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 81 }
        try await deviceA.engine.push()
        clock.advance(by: 10)
        try deviceB.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 79 }   // later than A's

        // Pull before push: the pending row must not be overwritten.
        let report = try await deviceB.engine.sync()

        #expect(report.pushed == 1)
        #expect(await server.row(.bodyMeasurements, id: row.id)?["weight_kg"] == .int(79))
        try await deviceA.engine.sync()
        #expect(try deviceA.fetch(BodyMeasurement.self, id: row.id)?.weightKg == 79)
    }

    @Test func tombstoneIsAppliedAndBeatsAnEdit() async throws {
        let pair = try await setUp()
        let (server, deviceA, deviceB, row) = (pair.server, pair.deviceA, pair.deviceB, pair.row)
        clock.advance(by: 10)
        try deviceA.edit(BodyMeasurement.self, id: row.id) { $0.deletedAt = clock.now }
        try await deviceA.engine.sync()
        clock.advance(by: 10)
        try deviceB.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 70 }    // later, but the row is gone

        try await deviceB.engine.sync()

        let local = try #require(try deviceB.fetch(BodyMeasurement.self, id: row.id))
        #expect(local.deletedAt != nil)
        #expect(local.syncState == .synced)
        #expect(await server.row(.bodyMeasurements, id: row.id)?["deleted_at"]?.isNull == false)
        #expect(try await deviceB.measurements.all(userId: testUser).isEmpty)
    }

    @Test func localTombstoneIsNotUndoneByAnOlderRemoteEdit() async throws {
        let pair = try await setUp()
        let (server, deviceA, deviceB, row) = (pair.server, pair.deviceA, pair.deviceB, pair.row)
        clock.advance(by: 10)
        try deviceA.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 85 }
        try await deviceA.engine.sync()
        clock.advance(by: 10)
        try deviceB.edit(BodyMeasurement.self, id: row.id) { $0.deletedAt = clock.now }

        try await deviceB.engine.sync()

        #expect(await server.row(.bodyMeasurements, id: row.id)?["deleted_at"]?.isNull == false)
    }

    @Test func oneBadRowFailsWithItsReasonAndTheRestStillLand() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let device = try SyncDevice(server: server, clock: clock)
        let good = (0..<3).map { measurement(80 + Double($0), on: clock.now, now: clock.now) }
        let bad = measurement(500, on: clock.now, now: clock.now)
        try device.insert(good + [bad])
        await server.reject(id: bad.id, reason: "body_measurements_weight_check")

        let report = try await device.engine.sync()

        #expect(report.pushed == 3)
        #expect(report.failed == 1)
        #expect(try device.fetch(BodyMeasurement.self, id: bad.id)?.syncState == .failed)
        #expect(await device.metadata.failureReason(id: bad.id)?.contains("weight_check") == true)
        #expect(try await device.engine.failedCount() == 1)
        // A plain sync leaves it alone; "sync now" retries it.
        #expect(try await device.engine.sync().pushed == 0)
        await server.accept(id: bad.id)
        #expect(try await device.engine.sync(retryFailed: true).pushed == 1)
        #expect(await device.metadata.failureReason(id: bad.id) == nil)
        #expect(try device.fetch(BodyMeasurement.self, id: bad.id)?.syncState == .synced)
    }

    @Test func childOfAFailedParentFailsInsteadOfBlockingTheQueue() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let device = try SyncDevice(server: server, clock: clock)
        let routine = Routine(userId: testUser, name: "R", now: clock.now)
        let day = RoutineDay(userId: testUser, routineId: routine.id, position: 0, name: "A", now: clock.now)
        try device.insert([routine, day, measurement(80, on: clock.now, now: clock.now)])
        await server.reject(id: routine.id)

        let report = try await device.engine.sync()

        #expect(report.pushed == 1)
        #expect(report.failed == 2)
        #expect(await device.metadata.failureReason(id: day.id)?.contains("foreign key") == true)
    }

    @Test func clockSkewIsCorrectedWhenComparingEdits() async throws {
        // The device clock runs an hour behind the server.
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let deviceA = try SyncDevice(server: server, clock: clock)
        let lagging = TestClock(clock.now.addingTimeInterval(-3_600))
        let deviceB = try SyncDevice(server: server, clock: lagging)
        let row = measurement(80, on: clock.now, now: clock.now)
        try deviceA.insert([row])
        try await deviceA.engine.sync()
        try await deviceB.engine.sync()

        clock.advance(by: 10)
        lagging.advance(by: 10)
        try deviceA.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 81 }
        try await deviceA.engine.sync()
        clock.advance(by: 10)
        lagging.advance(by: 10)
        // Really 10 s after A's edit, but stamped 59 min "earlier" by the slow clock.
        try deviceB.edit(BodyMeasurement.self, id: row.id) { $0.weightKg = 79 }

        try await deviceB.engine.sync()

        #expect(abs(await deviceB.metadata.snapshot.clockOffset - 3_600) < 1)
        #expect(await server.row(.bodyMeasurements, id: row.id)?["weight_kg"] == .int(79))
    }

    @Test func activeWorkoutIsHeldBackUntilItEnds() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let device = try SyncDevice(server: server, clock: clock)
        let workout = try await device.workouts.start(WorkoutDraft(startedAt: clock.now, exercises: [
            WorkoutExerciseDraft(ref: .catalog("bench_press"), sets: [SetInput(weightKg: 60, reps: 8, isCompleted: true)])
        ]), userId: testUser)
        let setId = try #require(workout.exercises.first?.sets.first?.id)
        let record = PersonalRecord(
            userId: testUser, ref: .catalog("bench_press"), kind: .weight, value: 60, setId: setId, date: clock.now, now: clock.now
        )
        try device.insert([record])

        let during = try await device.engine.sync()

        #expect(during.pushed == 0)
        #expect(await server.rowCount(.workouts) == 0)
        #expect(await server.rowCount(.personalRecords) == 0)
        #expect(try await device.engine.pendingCount() == 4)

        clock.advance(by: 1_800)
        _ = try await device.workouts.finish(id: workout.id, at: clock.now)
        let after = try await device.engine.sync()

        #expect(after.pushed == 4)
        #expect(await server.row(.sets, id: setId) != nil)
    }

    @Test func pullLeavesTheActiveWorkoutAlone() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let device = try SyncDevice(server: server, clock: clock)
        let workout = try await device.workouts.start(WorkoutDraft(name: "Mine", startedAt: clock.now), userId: testUser)
        var remote = try SyncCoding.encode(try #require(try device.fetch(Workout.self, id: workout.id)).makeDTO())
        remote["name"] = .string("Theirs")
        remote["ended_at"] = .string(SyncTime.timestamp(clock.now.addingTimeInterval(60)))
        clock.advance(by: 120)
        await server.seed(.workouts, row: remote)

        let report = try await device.engine.sync()

        #expect(report.skippedLocked == 1)
        #expect(try device.fetch(Workout.self, id: workout.id)?.name == "Mine")
        #expect(try device.fetch(Workout.self, id: workout.id)?.endedAt == nil)
    }

    @Test func pagedPullResumesFromTheStoredCursor() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let writer = try SyncDevice(server: server, clock: clock)
        try writer.insert((0..<5).map { measurement(70 + Double($0), on: clock.now, now: clock.now) })
        try await writer.engine.push()
        let reader = try SyncDevice(server: server, clock: clock, pageSize: 2)
        await server.setOffline(false)

        let report = try await reader.engine.restore()

        #expect(report.pulled == 5)
        #expect(await reader.metadata.cursor(for: .bodyMeasurements) != nil)
        // A new row after the cursor is the only thing the next pass fetches.
        try writer.insert([measurement(90, on: clock.now, now: clock.now)])
        try await writer.engine.push()
        #expect(try await reader.engine.sync().pulled == 1)
    }

    @Test func rowsOfAnotherUserAreRefusedByTheServer() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let device = try SyncDevice(server: server, clock: clock, userId: otherUser)
        try device.insert([measurement(80, on: clock.now, now: clock.now, userId: otherUser)])

        let report = try await device.engine.sync()

        #expect(report.failed == 1)
    }

    @Test func timestampsRoundTripServerFormats() throws {
        let date = try #require(SyncTime.parseTimestamp("2026-11-13T10:00:00.123456+00:00"))
        #expect(SyncTime.timestamp(date) == "2026-11-13T10:00:00.123456Z")
        #expect(SyncTime.parseTimestamp("2026-11-13T10:00:00Z") == SyncTime.parseTimestamp("2026-11-13 10:00:00+00"))
        let whole = try #require(SyncTime.parseTimestamp("2026-11-13T10:00:00Z"))
        #expect(SyncTime.parseTimestamp("2026-11-13T10:00:00.5Z")?.timeIntervalSince(whole) == 0.5)
        let day = try #require(SyncTime.parseDay("2026-02-03"))
        #expect(SyncTime.day(day) == "2026-02-03")
    }
}
