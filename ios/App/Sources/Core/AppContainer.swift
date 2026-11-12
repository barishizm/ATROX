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
    let appearance: AppearanceSettings
    /// Fake until the export/delete Edge Functions exist (after P045).
    let accountService: any AccountService
    let authFlow: AuthFlowModel
    let passwordRecovery: PasswordRecoveryModel
    /// Local SwiftData store (app group container); nil only in tests that do not need persistence.
    let modelContainer: ModelContainer?
    /// Apple Health (P023); `UnavailableHealthService` where Health does not exist.
    let health: any HealthService

    init(
        featureFlags: FeatureFlags = FeatureFlags(),
        sessionService: any SessionService,
        authService: (any AuthService)? = nil,
        language: LanguageSettings = LanguageSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        accountService: any AccountService = FakeAccountService(),
        modelContainer: ModelContainer? = nil,
        health: any HealthService = UnavailableHealthService()
    ) {
        self.health = health
        self.modelContainer = modelContainer
        self.featureFlags = featureFlags
        self.sessionService = sessionService
        self.authService = authService
        self.language = language
        self.appearance = appearance
        self.accountService = accountService
        let root = AppRootModel(service: sessionService)
        self.root = root
        self.authFlow = AuthFlowModel(
            service: authService ?? NotConfiguredAuthService(),
            localeCode: { [language] in language.effectiveLocale().language.languageCode?.identifier },
            onSignedIn: { user in root.didSignIn(onboardingComplete: user.onboardingComplete) }
        )
        self.passwordRecovery = PasswordRecoveryModel(service: authService)
    }

    /// The signed-in user, or nil when signed out / auth is not configured.
    private func currentUser() async -> AuthUser? {
        guard let authService else { return nil }
        switch await authService.restoreSession() {
        case .signedIn(let user), .passwordRecovery(let user): return user
        case .signedOut: return nil
        }
    }

    /// Builds the onboarding model for the signed-in user; nil when there is no user or no local store.
    func makeOnboardingModel() async -> OnboardingViewModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        return OnboardingViewModel(
            userId: user.id,
            store: UserDefaultsOnboardingDraftStore(),
            profiles: SwiftDataProfileRepository(modelContainer: modelContainer),
            measurements: SwiftDataMeasurementRepository(modelContainer: modelContainer),
            consents: ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer)),
            health: health,
            localeCode: language.effectiveLocale().language.languageCode?.identifier ?? "en"
        )
    }

    /// Builds the Profile tab's model for the signed-in user; nil when there is no user or no local store.
    func makeProfileModel() async -> ProfileModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        return ProfileModel(
            userId: user.id,
            email: user.email,
            profiles: SwiftDataProfileRepository(modelContainer: modelContainer),
            measurements: SwiftDataMeasurementRepository(modelContainer: modelContainer),
            settings: SwiftDataSettingsRepository(modelContainer: modelContainer),
            consents: ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer)),
            appearance: appearance,
            health: health
        )
    }

    func makeAccountModel(userId: UUID) -> AccountModel {
        AccountModel(
            userId: userId,
            service: accountService,
            confirmationWord: DeleteConfirmation.word(for: language.effectiveLocale())
        ) { [root] in await root.signOut() }
    }

    /// Production wiring.
    static func live(bundle: Bundle = .main) -> AppContainer {
        #if DEBUG
        // UI tests run against an in-memory auth service instead of a real backend.
        if ProcessInfo.processInfo.arguments.contains("-uitest-fake-auth") {
            // `-uitest-onboarded` starts signed in with a finished profile so tests can open the main tabs directly.
            let onboarded = ProcessInfo.processInfo.arguments.contains("-uitest-onboarded")
            let user = AuthUser(id: UUID(), email: "ada@example.com", isEmailConfirmed: true, onboardingComplete: onboarded)
            let fake = FakeAuthService(initial: onboarded ? .signedIn(user) : .signedOut)
            let store = try? DataStore.inMemory()
            if onboarded, let store { seedUITestData(in: store, userId: user.id) }
            return AppContainer(
                sessionService: AuthSessionService(auth: fake), authService: fake,
                accountService: FakeAccountService(), modelContainer: store, health: uiTestHealth()
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
            sessionService: AuthSessionService(auth: auth), authService: auth, modelContainer: store,
            health: HealthKitService()
        )
    }

    #if DEBUG
    /// `-uitest-fake-health`: a Health with sample data; otherwise Health is absent and its buttons stay hidden.
    private static func uiTestHealth() -> any HealthService {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-fake-health") else { return UnavailableHealthService() }
        let birth = Calendar.current.date(byAdding: .year, value: -31, to: Date()) ?? Date()
        // Today, so it is not older than the seeded weigh-in (imports start at the newest local day).
        let weighIn = Date()
        return FakeHealthService(
            profile: HealthBodyProfile(heightCm: 182, weightKg: 84.5, birthDate: birth, sex: .male),
            samples: [HealthWeightSample(date: weighIn, weightKg: 84.5, isFromThisApp: false)]
        )
    }

    /// A profile and two weigh-ins for UI tests (inserted directly: the repositories are async).
    private static func seedUITestData(in container: ModelContainer, userId: UUID) {
        let context = ModelContext(container)
        let now = Date()
        let birth = Calendar.current.date(byAdding: .year, value: -28, to: now) ?? now
        context.insert(UserProfile(userId: userId, input: ProfileInput(
            firstName: "Ada", lastName: "Lovelace", birthDate: birth, sex: .female, heightCm: 170,
            experience: .twoToFiveYears, goal: .strength, weeklyFrequency: 4, equipmentAccess: .fullGym
        )))
        for (days, kg) in [(14.0, 62.0), (0.0, 61.0)] {
            let date = now.addingTimeInterval(-days * 86_400)
            context.insert(BodyMeasurement(userId: userId, input: MeasurementInput(date: date, weightKg: kg)))
        }
        try? context.save()
    }
    #endif

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
