import DataKit
import Foundation
import Observation
import SwiftData

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
    /// Local SwiftData store (app group container); nil only in tests that do not need persistence.
    let modelContainer: ModelContainer?

    init(
        featureFlags: FeatureFlags = FeatureFlags(),
        sessionService: any SessionService,
        authService: (any AuthService)? = nil,
        language: LanguageSettings = LanguageSettings(),
        modelContainer: ModelContainer? = nil
    ) {
        self.modelContainer = modelContainer
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

    /// Builds the onboarding model for the signed-in user; nil when there is no user or no local store.
    func makeOnboardingModel() async -> OnboardingViewModel? {
        guard let modelContainer, let authService else { return nil }
        let user: AuthUser
        switch await authService.restoreSession() {
        case .signedIn(let signedIn), .passwordRecovery(let signedIn): user = signedIn
        case .signedOut: return nil
        }
        return OnboardingViewModel(
            userId: user.id,
            store: UserDefaultsOnboardingDraftStore(),
            profiles: SwiftDataProfileRepository(modelContainer: modelContainer),
            measurements: SwiftDataMeasurementRepository(modelContainer: modelContainer),
            consents: ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer)),
            localeCode: language.effectiveLocale().language.languageCode?.identifier ?? "en"
        )
    }

    /// Production wiring.
    static func live(bundle: Bundle = .main) -> AppContainer {
        #if DEBUG
        // UI tests run against an in-memory auth service instead of a real backend.
        if ProcessInfo.processInfo.arguments.contains("-uitest-fake-auth") {
            let fake = FakeAuthService()
            return AppContainer(
                sessionService: AuthSessionService(auth: fake), authService: fake,
                modelContainer: try? DataStore.inMemory()
            )
        }
        #endif
        let info = bundle.infoDictionary ?? [:]
        let store = makeStore(appGroupID: info["AppGroupID"] as? String)
        guard let config = SupabaseConfiguration(
            infoDictionary: info, urlScheme: info["AppURLScheme"] as? String
        ) else {
            Log.app.error("Supabase is not configured; running signed out. See docs/KURULUM.md.")
            return AppContainer(sessionService: PlaceholderSessionService(), modelContainer: store)
        }
        let auth = SupabaseAuthService(
            configuration: config, apple: AppleIDTokenProvider(), google: GoogleIDTokenProvider()
        )
        return AppContainer(
            sessionService: AuthSessionService(auth: auth), authService: auth, modelContainer: store
        )
    }

    /// App group store; if the group is missing (unsigned build) fall back to the app's own sandbox.
    private static func makeStore(appGroupID: String?) -> ModelContainer? {
        do {
            if let appGroupID { return try DataStore.production(appGroupID: appGroupID) }
            Log.app.error("AppGroupID missing from Info.plist; using the app sandbox for local data.")
            return try DataStore.onDisk(directory: URL.homeDirectory)
        } catch {
            Log.app.error("App group store unavailable (\(error)); using the app sandbox for local data.")
            return try? DataStore.onDisk(directory: URL.homeDirectory)
        }
    }
}
