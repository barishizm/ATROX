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
    let authFlow: AuthFlowModel
    let passwordRecovery: PasswordRecoveryModel

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
        let root = AppRootModel(service: sessionService)
        self.root = root
        self.authFlow = AuthFlowModel(
            service: authService ?? NotConfiguredAuthService(),
            localeCode: { [language] in language.effectiveLocale().language.languageCode?.identifier },
            onSignedIn: { user in root.didSignIn(onboardingComplete: user.onboardingComplete) }
        )
        self.passwordRecovery = PasswordRecoveryModel(service: authService)
    }

    /// Production wiring.
    static func live(bundle: Bundle = .main) -> AppContainer {
        #if DEBUG
        // UI tests run against an in-memory auth service instead of a real backend.
        if ProcessInfo.processInfo.arguments.contains("-uitest-fake-auth") {
            let fake = FakeAuthService()
            return AppContainer(sessionService: AuthSessionService(auth: fake), authService: fake)
        }
        #endif
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
