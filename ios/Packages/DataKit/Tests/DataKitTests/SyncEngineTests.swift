@testable import DataKit
import Foundation
import SwiftData
import Testing

/// One "device": its own local store, clock and engine, talking to a shared fake server.
struct SyncDevice {
    let container: ModelContainer
    let clock: TestClock
    let metadata = SyncMetadataStore()
    let engine: SyncEngine

    init(server: InMemoryRemoteStore, clock: TestClock, userId: UUID = testUser, pageSize: Int = 500, chunkSize: Int = 200) throws {
        container = try DataStore.inMemory()
        self.clock = clock
        engine = SyncEngine(
            userId: userId, modelContainer: container, remote: server, metadata: metadata, clock: clock.closure,
            chunkSize: chunkSize, pageSize: pageSize
        )
    }

    var workouts: SwiftDataWorkoutRepository { SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure) }
    var measurements: SwiftDataMeasurementRepository { SwiftDataMeasurementRepository(modelContainer: container, clock: clock.closure) }

    func insert(_ models: [any PersistentModel]) throws {
        let context = ModelContext(container)
        for model in models { context.insert(model) }
        try context.save()
    }

    func fetch<M: SyncableModel>(_ type: M.Type, id: UUID) throws -> M? {
        try ModelContext(container).fetch(M.syncDescriptor(.id(id))).first
    }

    func edit<M: SyncableModel>(_ type: M.Type, id: UUID, _ change: (M) -> Void) throws {
        let context = ModelContext(container)
        let model = try #require(try context.fetch(M.syncDescriptor(.id(id))).first)
        change(model)
        model.markPending(at: clock.now)
        try context.save()
    }
}

func measurement(_ kg: Double, on day: Date, now: Date, userId: UUID = testUser) -> BodyMeasurement {
    BodyMeasurement(userId: userId, input: MeasurementInput(date: day, weightKg: kg), now: now)
}

@Suite("SyncEngine (P044)")
struct SyncEngineTests {
    let serverClock = TestClock()

    private func server() -> InMemoryRemoteStore { InMemoryRemoteStore(userId: testUser, clock: serverClock.closure) }

    @Test func pushesPendingRowsInDependencyOrderAndMarksThemSynced() async throws {
        let server = server()
        let device = try SyncDevice(server: server, clock: TestClock())
        let now = device.clock.now
        let routine = Routine(userId: testUser, name: "PPL", now: now)
        let day = RoutineDay(userId: testUser, routineId: routine.id, position: 0, name: "Push", now: now)
        let custom = CustomExercise(userId: testUser, input: CustomExerciseInput(name: "Landmine", primaryMuscles: ["chest"]), now: now)
        let item = RoutineExercise(userId: testUser, routineDayId: day.id, position: 0, ref: .custom(custom.id), now: now)
        // Inserted children first: the engine must still push parents before them (the fake server checks keys).
        try device.insert([item, day, routine, custom, measurement(80, on: now, now: now)])

        let report = try await device.engine.sync()

        #expect(report.pushed == 5)
        #expect(report.failed == 0)
        #expect(await server.rowCount(.routineExercises) == 1)
        let stored = try #require(await server.row(.routineExercises, id: item.id))
        #expect(stored["custom_exercise_id"] == .string(custom.id.uuidString))
        #expect(stored["target_reps_min"] == .null)
        let local = try #require(try device.fetch(RoutineExercise.self, id: item.id))
        #expect(local.syncState == .synced)
        #expect(SyncTime.timestamp(local.updatedAt) == stored.rowUpdatedAt)
        #expect(try await device.engine.pendingCount() == 0)
    }

    @Test func offlineChangesQueueUpAndGoOutWhenBackOnline() async throws {
        let server = server()
        let device = try SyncDevice(server: server, clock: TestClock())
        let row = try await device.measurements.add(MeasurementInput(date: device.clock.now, weightKg: 81), userId: testUser)
        await server.setOffline(true)

        await #expect(throws: RemoteStoreError.transient("offline")) { try await device.engine.sync() }
        device.clock.advance(by: 60)
        _ = try await device.measurements.update(id: row.id, with: MeasurementInput(date: device.clock.now, weightKg: 80.5))
        #expect(try await device.engine.pendingCount() == 1)
        #expect(await server.rowCount(.bodyMeasurements) == 0)

        await server.setOffline(false)
        let report = try await device.engine.sync()

        #expect(report.pushed == 1)
        #expect(await server.row(.bodyMeasurements, id: row.id)?["weight_kg"] == .number(80.5))
        #expect(try device.fetch(BodyMeasurement.self, id: row.id)?.syncState == .synced)
    }

    @Test func dataMovesBetweenTwoDevices() async throws {
        let server = server()
        let deviceA = try SyncDevice(server: server, clock: TestClock())
        let deviceB = try SyncDevice(server: server, clock: TestClock())
        let start = deviceA.clock.now
        let workout = try await deviceA.workouts.start(WorkoutDraft(
            name: "Legs", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            exercises: [WorkoutExerciseDraft(ref: .catalog("barbell_squat"), sets: [
                SetInput(weightKg: 100, reps: 5, isCompleted: true), SetInput(weightKg: 102.5, reps: 5, isCompleted: true)
            ])]
        ), userId: testUser)
        try await deviceA.engine.sync()

        let collector = ProgressCollector()
        try await deviceB.engine.restore { collector.append($0) }
        let progress = collector.values

        let copy = try #require(try await deviceB.workouts.workout(id: workout.id))
        #expect(copy.name == "Legs")
        #expect(copy.exercises.first?.sets.map(\.input.weightKg) == [100, 102.5])
        #expect(progress.first == SyncProgress(done: 0, total: 4))
        #expect(progress.last?.fraction == 1)
        #expect(await deviceB.metadata.snapshot.restoreCompleted)
    }

    @Test func ownEchoDoesNotChangeAnything() async throws {
        let server = server()
        let device = try SyncDevice(server: server, clock: TestClock())
        try device.insert([measurement(80, on: device.clock.now, now: device.clock.now)])
        let first = try await device.engine.sync()
        let second = try await device.engine.sync()
        let third = try await device.engine.sync()

        // The second pass pulls back its own row with the same server stamp: nothing to apply.
        #expect(first.pushed == 1)
        #expect(second.pushed == 0)
        #expect(second.pulled == 0)
        #expect(second.keptLocal == 1)
        #expect(third == SyncReport())
    }
}

final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SyncProgress] = []
    func append(_ value: SyncProgress) { lock.withLock { items.append(value) } }
    var values: [SyncProgress] { lock.withLock { items } }
}
