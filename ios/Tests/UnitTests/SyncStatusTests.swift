import DataKit
import Foundation
import SwiftData
import Testing

@testable import ATROX

@MainActor
struct SyncStatusTests {
    @Test func headlineFollowsThePhaseAndPendingRows() {
        #expect(SyncStatusPresenter.headline(phase: .idle, pending: 0) == .upToDate)
        #expect(SyncStatusPresenter.headline(phase: .idle, pending: 3) == .pending(3))
        #expect(SyncStatusPresenter.headline(phase: .syncing, pending: 3) == .syncing)
        #expect(SyncStatusPresenter.headline(phase: .waitingToRetry, pending: 1) == .offline)
        #expect(SyncStatusPresenter.headline(phase: .failed("x"), pending: 0) == .failed)
        let restoring = SyncCoordinator.Phase.restoring(SyncProgress(done: 2, total: 9))
        #expect(SyncStatusPresenter.headline(phase: restoring, pending: 0) == .restoring(done: 2, total: 9))
    }

    @Test func failedRowsOrAFailedPassShowAnError() {
        #expect(SyncStatusPresenter.tone(phase: .idle, failedRows: 0) == .normal)
        #expect(SyncStatusPresenter.tone(phase: .idle, failedRows: 1) == .error)
        #expect(SyncStatusPresenter.tone(phase: .failed("x"), failedRows: 0) == .error)
        #expect(SyncStatusPresenter.tone(phase: .waitingToRetry, failedRows: 0) == .warning)
    }

    @Test func syncNowIsHiddenWhileAPassRuns() {
        #expect(SyncStatusPresenter.canSyncNow(phase: .idle))
        #expect(SyncStatusPresenter.canSyncNow(phase: .failed("x")))
        #expect(!SyncStatusPresenter.canSyncNow(phase: .syncing))
        #expect(!SyncStatusPresenter.canSyncNow(phase: .restoring(SyncProgress(done: 0, total: 0))))
    }

    /// Sign-out from the container wipes the device copy before the session ends.
    @Test func containerSignOutWipesLocalRows() async throws {
        let store = try DataStore.inMemory()
        let userId = UUID()
        let remote = InMemoryRemoteStore(userId: userId)
        let metadata = SyncMetadataStore()
        let sync = SyncCoordinator(modelContainer: store, metadata: metadata) { id in
            SyncEngine(userId: id, modelContainer: store, remote: remote, metadata: metadata)
        }
        let user = AuthUser(id: userId, email: "a@example.com", isEmailConfirmed: true, onboardingComplete: true)
        let auth = FakeAuthService(initial: .signedIn(user))
        let container = AppContainer(
            sessionService: AuthSessionService(auth: auth), authService: auth, modelContainer: store, sync: sync
        )
        await container.root.start()
        await container.sessionChanged(container.root.state)
        await sync.waitUntilIdle()
        let measurements = SwiftDataMeasurementRepository(modelContainer: store)
        _ = try await measurements.add(MeasurementInput(date: Date(), weightKg: 80), userId: userId)

        await container.signOut()

        #expect(try ModelContext(store).fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        #expect(container.root.state == .signedOut)
        #expect(sync.userId == nil)
    }
}
