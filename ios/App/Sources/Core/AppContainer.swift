import DataKit
import Foundation
import Observation

/// Composition root: holds the app's dependencies and is handed down via `Environment`.
/// Tests build one with fakes through `init`.
@MainActor
@Observable
final class AppContainer {
    let featureFlags: FeatureFlags
    let sessionService: any SessionService
    /// nil when Supabase is not configured (fresh clone without Secrets.xcconfig).
    let authService: (any AuthService)?
    let root: AppRootModel
    let language: LanguageSettings

    init(
        featureFlags: FeatureFlags = FeatureFlags(),
        sessionService: any SessionService,
        authService: (any AuthService)? = nil,
        language: LanguageSettings = LanguageSettings()
    ) {
        self.featureFlags = featureFlags
        self.sessionService = sessionService
        self.authService = authService
        self.language = language
        self.root = AppRootModel(service: sessionService)
    }

    /// Production wiring.
    static func live(bundle: Bundle = .main) -> AppContainer {
        let info = bundle.infoDictionary ?? [:]
        guard let config = SupabaseConfiguration(
            infoDictionary: info, urlScheme: info["AppURLScheme"] as? String
        ) else {
            Log.app.error("Supabase is not configured; running signed out. See docs/KURULUM.md.")
            return AppContainer(sessionService: PlaceholderSessionService())
        }
        let auth = SupabaseAuthService(
            configuration: config, apple: AppleIDTokenProvider(), google: GoogleIDTokenProvider()
        )
        return AppContainer(sessionService: AuthSessionService(auth: auth), authService: auth)
    }
}
