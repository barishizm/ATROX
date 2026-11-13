import DataKit
import Foundation
import StrengthKit

/// Hands the score service the model bundle in force: the downloaded one while it verifies, else the embedded base
/// bundle. Loading verifies signatures, so the result is kept until the active version changes.
actor ScoringModelProvider {
    private let updater: ModelUpdater?
    private let appVersion: String
    private var cached: (key: String, value: ScoringModel)?

    init(updater: ModelUpdater?, appVersion: String) {
        self.updater = updater
        self.appVersion = appVersion
    }

    func current() async -> ScoringModel? {
        let key = await updater?.activeVersion ?? "embedded"
        if let cached, cached.key == key { return cached.value }
        let bundle: ModelBundle?
        if let updater {
            bundle = try? await updater.currentBundle()
        } else {
            bundle = try? ModelBundle.embedded(appVersion: appVersion)
        }
        guard let bundle else { return nil }
        let value = ScoringModel(model: bundle.model, version: bundle.manifest.version)
        cached = (key, value)
        return value
    }
}
