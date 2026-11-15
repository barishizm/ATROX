import DataKit
import Foundation
import SwiftData

/// Sync wiring of the composition root (P044/P045).
extension AppContainer {
    /// Every save of a SwiftData context (repositories, the sync engine itself) asks for a debounced sync; the
    /// coordinator skips it when nothing is pending.
    func observeLocalSaves() {
        guard sync != nil || scoreService != nil else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            // Saves of the scores' own output (snapshots, insights) still sync but cannot change a score.
            let affectsScores = ScoreTrigger.isRelevant(saveNotification: note)
            let wroteConsent = Self.savedConsents(note)
            MainActor.assumeIsolated {
                self?.sync?.noteLocalChange()
                if affectsScores { self?.scoresMayHaveChanged() }
                if wroteConsent { self?.pushConsents() }
            }
        }
    }

    /// Whether a save inserted a consent row (a grant or a withdrawal) that the server has to learn about.
    nonisolated static func savedConsents(_ note: Notification) -> Bool {
        let inserted = note.userInfo?[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
        return inserted.contains { $0.entityName == String(describing: ConsentRecord.self) }
    }

    /// Sends pending consent rows to the server; a failure leaves them pending for the next trigger.
    func pushConsents() {
        guard let consentPusher else { return }
        Task { [weak self] in
            guard let user = await self?.currentUser() else { return }
            await consentPusher.push(userId: user.id)
        }
    }

    /// Follows the root session state: a signed-in user gets the sync running (with the first restore).
    func sessionChanged(_ state: SessionState) async {
        switch state {
        case .ready, .needsOnboarding:
            sessionIsOpen = true
            if case .ready = state { Task { [weak self] in await self?.prepareScores() } }
            guard let sync else { return }
            pushConsents()
            if let user = await currentUser() { await sync.activate(userId: user.id) }
        case .signedOut:
            await sessionEndedExternally()
        case .loading:
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
