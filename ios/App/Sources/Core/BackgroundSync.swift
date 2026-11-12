import BackgroundTasks
import DataKit
import Foundation

/// Opportunistic background sync with `BGAppRefreshTask` (P045). Registered at launch; the coordinator is attached once
/// the container exists. The identifier is listed under `BGTaskSchedulerPermittedIdentifiers` in project.yml.
@MainActor
final class BackgroundSync {
    static let identifier = "com.barishizm.atrox.sync.refresh"
    static let shared = BackgroundSync()

    weak var coordinator: SyncCoordinator?

    /// Must run before the app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let refresh = task as? BGAppRefreshTask else { return task.setTaskCompleted(success: false) }
                BackgroundSync.shared.handle(refresh)
            }
        }
    }

    /// Asks for the next run in about 15 minutes (the system decides when).
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.app.info("Background sync not scheduled: \(error.localizedDescription)", privacy: .public)
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        guard let coordinator, coordinator.isAvailable else { return task.setTaskCompleted(success: false) }
        let work = Task { await coordinator.backgroundSync() }
        task.expirationHandler = { work.cancel() }
        Task { task.setTaskCompleted(success: await work.value) }
    }
}
