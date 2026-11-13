import DataKit
import Foundation
import SwiftData

/// Sync wiring of the composition root (P044/P045).
extension AppContainer {
    /// Every save of a SwiftData context (repositories, the sync engine itself) asks for a debounced sync; the
    /// coordinator skips it when nothing is pending.
    func observeLocalSaves() {
        guard sync != nil || scoreService != nil else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sync?.noteLocalChange()
                self?.scoresMayHaveChanged()
            }
        }
    }

    /// Follows the root session state: a signed-in user gets the sync running (with the first restore).
    func sessionChanged(_ state: SessionState) async {
        if case .ready = state { Task { [weak self] in await self?.prepareScores() } }
        guard let sync else { return }
        switch state {
        case .ready, .needsOnboarding:
            if let user = await currentUser() { await sync.activate(userId: user.id) }
        case .loading, .signedOut:
            break
        }
    }

    /// The sync coordinator over the local store; its bookkeeping file sits next to the store.
    static func makeSync(store: ModelContainer, appGroupID: String?, remote: some RemoteStore) -> SyncCoordinator {
        let directory = appGroupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? URL.homeDirectory
        let metadata = SyncMetadataStore.file(in: directory)
        return SyncCoordinator(
            modelContainer: store, metadata: metadata, network: { NetworkPathMonitor.updates() },
            makeEngine: { userId in SyncEngine(userId: userId, modelContainer: store, remote: remote, metadata: metadata) }
        )
    }
}
