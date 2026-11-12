@testable import DataKit
import Foundation
import SwiftData
import Testing

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [Duration] = []
    var durations: [Duration] { lock.withLock { log } }
    func record(_ duration: Duration) { lock.withLock { log.append(duration) } }
}

/// Polls until `condition` holds (the coordinator works in unstructured tasks).
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

@MainActor
@Suite("SyncCoordinator (P045)")
struct SyncCoordinatorTests {
    let clock = TestClock()

    private func make(
        server: InMemoryRemoteStore, container: ModelContainer, metadata: SyncMetadataStore = SyncMetadataStore(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in throw CancellationError() },
        network: (@Sendable () -> AsyncStream<Bool>)? = nil
    ) -> SyncCoordinator {
        let clock = clock
        return SyncCoordinator(
            modelContainer: container, metadata: metadata, network: network, sleep: sleep, random: { 0.5 },
            makeEngine: { userId in
                SyncEngine(userId: userId, modelContainer: container, remote: server, metadata: metadata, clock: clock.closure)
            }
        )
    }

    @Test func backoffGrowsExponentiallyWithJitterAndACap() {
        let schedule = SyncSchedule()
        #expect(schedule.backoff(attempt: 0, random: 0) == 1)
        #expect(schedule.backoff(attempt: 0, random: 0.999) < 2)
        #expect(schedule.backoff(attempt: 3, random: 0.5) == 12)
        #expect(schedule.backoff(attempt: 20, random: 0) == 150)
        #expect(schedule.backoff(attempt: 20, random: 1) == 300)
    }

    @Test func signInRestoresEverythingThenSyncs() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let other = try SyncDevice(server: server, clock: clock)
        try other.insert((0..<3).map { measurement(80 + Double($0), on: clock.now, now: clock.now) })
        try await other.engine.push()
        let container = try DataStore.inMemory()
        let metadata = SyncMetadataStore()
        let coordinator = make(server: server, container: container, metadata: metadata)

        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()

        #expect(coordinator.phase == .idle)
        #expect(coordinator.lastSyncedAt != nil)
        #expect(await metadata.snapshot.restoreCompleted)
        #expect(try await SwiftDataMeasurementRepository(modelContainer: container).all(userId: testUser).count == 3)
    }

    @Test func anotherAccountsRowsAreWipedBeforeSigningIn() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let container = try DataStore.inMemory()
        let context = ModelContext(container)
        context.insert(measurement(70, on: clock.now, now: clock.now, userId: otherUser))
        context.insert(measurement(80, on: clock.now, now: clock.now, userId: testUser))
        try context.save()
        let coordinator = make(server: server, container: container)

        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()

        let left = try ModelContext(container).fetch(FetchDescriptor<BodyMeasurement>())
        #expect(left.isEmpty)
        #expect(await server.rowCount(.bodyMeasurements) == 0)
    }

    @Test func ownRowsFromBeforeSyncExistedAreKeptAndPushed() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let container = try DataStore.inMemory()
        let context = ModelContext(container)
        context.insert(measurement(80, on: clock.now, now: clock.now))
        try context.save()
        let coordinator = make(server: server, container: container)

        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()

        #expect(await server.rowCount(.bodyMeasurements) == 1)
        #expect(coordinator.pendingCount == 0)
    }

    @Test func requestsDuringAPassCollapseIntoOneFollowUp() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let coordinator = make(server: server, container: try DataStore.inMemory())

        await coordinator.activate(userId: testUser)
        coordinator.request(.foreground)
        coordinator.request(.workoutFinished)
        coordinator.request(.manual)
        await coordinator.waitUntilIdle()

        #expect(coordinator.passCount == 2)
    }

    @Test func transientFailureSchedulesABackoffRetryThatRecovers() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        await server.setOffline(true)
        let recorder = SleepRecorder()
        let coordinator = make(server: server, container: try DataStore.inMemory()) { duration in
            recorder.record(duration)
            await server.setOffline(false)
        }

        await coordinator.activate(userId: testUser)

        #expect(await eventually { coordinator.passCount == 2 })
        await coordinator.waitUntilIdle()
        #expect(coordinator.phase == .idle)
        // attempt 0 with random 0.5: 2 s step → 1.5 s.
        #expect(recorder.durations.first == .milliseconds(1_500))
    }

    @Test func localChangeWithNothingPendingDoesNotSync() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let container = try DataStore.inMemory()
        let coordinator = make(server: server, container: container, sleep: { _ in })
        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()
        let before = coordinator.passCount

        coordinator.noteLocalChange()
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.waitUntilIdle()
        #expect(coordinator.passCount == before)

        let measurements = SwiftDataMeasurementRepository(modelContainer: container)
        _ = try await measurements.add(MeasurementInput(date: clock.now, weightKg: 80), userId: testUser)
        coordinator.noteLocalChange()
        #expect(await eventually { coordinator.passCount == before + 1 })
        await coordinator.waitUntilIdle()
        #expect(await server.rowCount(.bodyMeasurements) == 1)
    }

    @Test func networkComingBackTriggersASync() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let coordinator = make(server: server, container: try DataStore.inMemory(), network: { stream })
        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()
        let before = coordinator.passCount

        continuation.yield(false)
        continuation.yield(true)

        #expect(await eventually { coordinator.passCount == before + 1 })
    }

    @Test func signOutReportsUnsyncedRowsThenWipesTheDevice() async throws {
        let server = InMemoryRemoteStore(userId: testUser, clock: clock.closure)
        let container = try DataStore.inMemory()
        let metadata = SyncMetadataStore()
        let coordinator = make(server: server, container: container, metadata: metadata)
        await coordinator.activate(userId: testUser)
        await coordinator.waitUntilIdle()
        await server.setOffline(true)
        let measurements = SwiftDataMeasurementRepository(modelContainer: container)
        _ = try await measurements.add(MeasurementInput(date: clock.now, weightKg: 80), userId: testUser)

        #expect(await coordinator.unsyncedCount() == 1)
        await coordinator.signOut()

        #expect(try ModelContext(container).fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        #expect(await metadata.snapshot == SyncMetadataStore.State())
        #expect(coordinator.userId == nil)
        #expect(!coordinator.isAvailable)
    }
}
