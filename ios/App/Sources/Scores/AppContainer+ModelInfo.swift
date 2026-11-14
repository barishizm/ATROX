import Foundation
import StrengthKit

/// The scoring model bundle in force, as the "How is it calculated?" screen shows it (P071).
struct ScoringModelInfo: Equatable {
    var version: String
    /// True once a downloaded bundle replaced the one shipped with the app.
    var isDownloaded: Bool
    var lastCheckedAt: Date?
}

extension AppContainer {
    /// Reads the real bundle (the downloaded one while it verifies, else the embedded one); nil when none loads.
    func scoringModelInfo() async -> ScoringModelInfo? {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        guard let bundle = await currentModelBundle(appVersion: appVersion) else { return nil }
        let downloaded = await modelUpdater?.activeVersion == bundle.manifest.version
        return ScoringModelInfo(version: bundle.manifest.version, isDownloaded: downloaded, lastCheckedAt: await modelUpdater?.lastCheckedAt)
    }

    /// "Check for updates" on the screen: asks the server now and recomputes scores when a new version arrives.
    func checkModelUpdateNow() async -> ModelUpdater.Outcome? {
        guard let modelUpdater else { return nil }
        let outcome = await modelUpdater.check()
        await prepareScores()
        return outcome
    }

    private func currentModelBundle(appVersion: String) async -> ModelBundle? {
        if let modelUpdater { return try? await modelUpdater.currentBundle() }
        return try? ModelBundle.embedded(appVersion: appVersion)
    }
}
