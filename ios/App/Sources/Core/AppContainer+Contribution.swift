import DataKit
import Foundation
import SwiftData

/// Anonymous contribution wiring of the composition root (P093).
extension AppContainer {
    static func makeContribution(
        store: ModelContainer?, scores: ScoreService?, transport: (any ContributionTransport)?
    ) -> ContributionService? {
        guard let store, let scores, let transport else { return nil }
        return ContributionService(
            consents: ConsentService(repository: SwiftDataConsentRepository(modelContainer: store)),
            keys: KeychainContributionKeyStore(), state: UserDefaultsContributionStateStore(),
            transport: transport, data: ScoreServiceContributionSource(scores: scores)
        )
    }

    /// Sends last month's summary when the user consented and it is due. Failures wait for the next launch.
    func sendContributionIfDue() async {
        guard let contribution, let user = await currentUser() else { return }
        do {
            try await contribution.sendIfDue(userId: user.id)
        } catch {
            Log.app.error("Contribution not sent: \(String(describing: error))")
        }
    }
}
