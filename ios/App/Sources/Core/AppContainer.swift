import Observation

/// Composition root: holds the app's dependencies and is handed down via `Environment`.
/// Tests build one with fakes through `init`.
@MainActor
@Observable
final class AppContainer {
    let featureFlags: FeatureFlags
    let sessionService: any SessionService
    let root: AppRootModel

    init(featureFlags: FeatureFlags = FeatureFlags(), sessionService: any SessionService) {
        self.featureFlags = featureFlags
        self.sessionService = sessionService
        self.root = AppRootModel(service: sessionService)
    }

    /// Production wiring.
    static func live() -> AppContainer {
        AppContainer(sessionService: PlaceholderSessionService())
    }
}
