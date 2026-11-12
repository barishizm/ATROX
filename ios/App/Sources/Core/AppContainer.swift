import DataKit
import Foundation
import Observation
import StrengthKit
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
    /// Export / account deletion: the Edge Functions in production (P045), a fake in tests and unconfigured builds.
    let accountService: any AccountService
    /// Sync with the server (P044/P045); nil without a local store. Inert (`isAvailable == false`) without Supabase.
    let sync: SyncCoordinator?
    @ObservationIgnored var saveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var workoutEventsTask: Task<Void, Never>?
    let authFlow: AuthFlowModel
    let passwordRecovery: PasswordRecoveryModel
    /// Local SwiftData store (app group container); nil only in tests that do not need persistence.
    let modelContainer: ModelContainer?
    /// Apple Health (P023); `UnavailableHealthService` where Health does not exist.
    let health: any HealthService
    /// Exercise catalog import and sync (P028); nil when there is no local store.
    let catalog: CatalogService?
    /// Public Storage bucket with the exercise images (P027); nil without Supabase.
    let exerciseImageBaseURL: URL?
    @ObservationIgnored private var planStores: [UUID: RoutinePlanStore] = [:]
    @ObservationIgnored private var workoutSession: WorkoutSession?
    /// Version counter and pending undo of the workout history (P042).
    let historyEvents = HistoryEvents()
    /// One rest timer for the app; it outlives the workout screen (minimizing keeps it running).
    let restTimer: RestTimerController = {
        let timer = RestTimerController(notifications: UserNotificationService())
        timer.onFinished = { RestCue.play() }
        return timer
    }()

    /// Workout Live Activity (P038); created together with the active-workout model.
    @ObservationIgnored private(set) var liveActivity: LiveActivityCoordinator?

    init(
        featureFlags: FeatureFlags = FeatureFlags(),
        sessionService: any SessionService,
        authService: (any AuthService)? = nil,
        language: LanguageSettings = LanguageSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        accountService: any AccountService = FakeAccountService(),
        modelContainer: ModelContainer? = nil,
        health: any HealthService = UnavailableHealthService(),
        catalog: CatalogService? = nil,
        exerciseImageBaseURL: URL? = nil,
        sync: SyncCoordinator? = nil
    ) {
        self.sync = sync
        self.exerciseImageBaseURL = exerciseImageBaseURL
        self.health = health
        self.catalog = catalog
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
        installRestIntentHandler()
        observeLocalSaves()
    }

    // MARK: Sync (P045)

    /// Sign-out from the UI: the device's copy of the user's data is removed, then the session ends.
    func signOut() async {
        workoutEventsTask?.cancel()
        workoutEventsTask = nil
        workoutSession = nil
        #if DEBUG
        debugUser = nil
        #endif
        await sync?.signOut()
        await root.signOut()
    }

    /// Lets the Live Activity buttons ("skip", "+15 s") drive the rest timer (P038).
    private func installRestIntentHandler() {
        RestCommandCenter.shared.handler = { [restTimer] command in
            switch command {
            case .skip: await restTimer.skip()
            case .adjust(let seconds): await restTimer.adjust(by: TimeInterval(seconds))
            }
        }
    }

    /// Installs the bundled catalog on first launch (or after an app update), then pulls newer exercises from the
    /// server. Runs off the main actor; an offline sync failure is not an error for the user.
    func prepareCatalog() async {
        guard let catalog else { return }
        do {
            let result = try await catalog.bootstrap()
            Log.app.info("Catalog bootstrap: \(String(describing: result))")
        } catch {
            Log.app.error("Catalog bootstrap failed: \(error)")
            return
        }
        do {
            let result = try await catalog.syncRemote()
            Log.app.info("Catalog sync: \(String(describing: result))")
        } catch {
            Log.app.error("Catalog sync failed (keeping the local catalog): \(error)")
        }
    }

    /// The signed-in user, or nil when signed out / auth is not configured.
    func currentUser() async -> AuthUser? {
        if let authService {
            switch await authService.restoreSession() {
            case .signedIn(let user), .passwordRecovery(let user): return user
            case .signedOut: break
            }
        }
        #if DEBUG
        return debugUser
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// Local-only user for the "pretend signed in" developer shortcut; there is no real session behind it.
    @ObservationIgnored private(set) var debugUser: AuthUser?

    func debugSignIn() {
        debugUser = AuthUser(id: UUID(), email: "debug@atrox.local", isEmailConfirmed: true, onboardingComplete: false)
        root.didSignIn(onboardingComplete: false)
    }
    #endif

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
            workouts: SwiftDataWorkoutRepository(modelContainer: modelContainer),
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

    /// Builds the exercise library's model; nil when there is no local store. The default equipment filter comes from
    /// the user's profile (full gym when there is none yet).
    func makeLibraryModel(catalogOnly: Bool = false) async -> LibraryModel? {
        guard let modelContainer else { return nil }
        var access = EquipmentAccess.fullGym
        let user = await currentUser()
        if let user,
           let profile = try? await SwiftDataProfileRepository(modelContainer: modelContainer).profile(userId: user.id) {
            access = profile.input.equipmentAccess
        }
        await ThumbnailLoader.shared.configure(storageBaseURL: exerciseImageBaseURL)
        return LibraryModel(modelContainer: modelContainer, equipmentAccess: access, userId: user?.id, catalogOnly: catalogOnly)
    }

    /// Detail screen of one exercise (catalog slug or custom exercise UUID); nil when there is no local store.
    func makeExerciseDetailModel(id: String) async -> ExerciseDetailModel? {
        guard let modelContainer else { return nil }
        await ThumbnailLoader.shared.configure(storageBaseURL: exerciseImageBaseURL)
        return ExerciseDetailModel(id: id, modelContainer: modelContainer, userId: await currentUser()?.id)
    }

    /// The user's programs (P033); nil when there is no user or no local store.
    func makeRoutineListModel() async -> RoutineListModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        return RoutineListModel(
            userId: user.id, repository: SwiftDataRoutineRepository(modelContainer: modelContainer),
            plan: planStore(for: user.id)
        )
    }

    /// Editor of one program (P033); nil when there is no user or no local store.
    func makeRoutineEditorModel(routineId: UUID) async -> RoutineEditorModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        let userId = user.id
        return RoutineEditorModel(
            routineId: routineId, repository: SwiftDataRoutineRepository(modelContainer: modelContainer),
            plan: planStore(for: userId)
        ) {
            let context = ModelContext(modelContainer)
            var items = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(ExerciseListItem.init)
            let own = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil })
            items += ((try? context.fetch(own)) ?? []).map(ExerciseListItem.init)
            return items
        }
    }

    /// Program templates (P034): the bundled templates, the exercise catalog for personalizing them and the user's
    /// profile for the recommendation; nil when there is no user, no local store or the template file is unreadable.
    func makeTemplateListModel() async -> TemplateListModel? {
        guard let modelContainer, let user = await currentUser(),
              let library = try? TemplateLibrary.bundled() else { return nil }
        let profile = try? await SwiftDataProfileRepository(modelContainer: modelContainer).profile(userId: user.id)
        let catalog = ((try? ModelContext(modelContainer).fetch(FetchDescriptor<Exercise>())) ?? [])
            .map(TemplateExerciseInfo.init)
        return TemplateListModel(
            userId: user.id, templates: library.templates, catalog: catalog, profile: profile?.input,
            repository: SwiftDataRoutineRepository(modelContainer: modelContainer), plan: planStore(for: user.id)
        )
    }

    /// The active workout engine (P035), shared by every screen. On first use it restores the user's active workout
    /// from the store, so a workout survives an app kill. nil when there is no user or no local store.
    func activeWorkoutSession() async -> WorkoutSession? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        if let workoutSession, workoutSession.userId == user.id { return workoutSession }
        let session = WorkoutSession(
            userId: user.id, workouts: SwiftDataWorkoutRepository(modelContainer: modelContainer),
            routines: SwiftDataRoutineRepository(modelContainer: modelContainer),
            records: SwiftDataPersonalRecordService(modelContainer: modelContainer)
        )
        session.progression = await progressionContext(userId: user.id, modelContainer: modelContainer)
        _ = try? await session.restore()
        workoutSession = session
        workoutEventsTask?.cancel()
        let events = session.events()
        workoutEventsTask = Task { [sync] in
            for await event in events {
                if case .workoutFinished = event { sync?.request(.workoutFinished) }
            }
        }
        return session
    }

    /// What the progression engine (P043) needs: the user's smallest loadable step and each catalog exercise's jump class.
    func progressionContext(userId: UUID, modelContainer: ModelContainer) async -> ProgressionContext {
        let profile = try? await SwiftDataProfileRepository(modelContainer: modelContainer).profile(userId: userId)
        let unit: WeightUnit = profile?.input.unitSystem == .imperial ? .pounds : .kilograms
        let context = ModelContext(modelContainer)
        let classes = Dictionary(
            ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map {
                ($0.id, LoadClass.classify(movementPattern: $0.movementPattern, mechanic: $0.mechanic))
            },
            uniquingKeysWith: { first, _ in first }
        )
        return ProgressionContext(
            roundingStepKg: unit.kilograms(from: PlateRounding.step(for: unit)),
            loadClass: { ref in
                if case .catalog(let id) = ref { return classes[id] ?? .upperCompound }
                return .upperCompound
            }
        )
    }

    /// Screen model of the active workout (P036) around the shared `WorkoutSession`; nil without user or store.
    func makeActiveWorkoutModel() async -> ActiveWorkoutModel? {
        guard let modelContainer, let user = await currentUser(), let session = await activeWorkoutSession() else { return nil }
        let profile = try? await SwiftDataProfileRepository(modelContainer: modelContainer).profile(userId: user.id)
        let unit: WeightUnit = profile?.input.unitSystem == .imperial ? .pounds : .kilograms
        let locale = language.effectiveLocale()
        let userId = user.id
        session.progression = await progressionContext(userId: userId, modelContainer: modelContainer)
        let model = ActiveWorkoutModel(
            session: session, unit: unit, showsRir: WorkoutPreferences.showsRir(),
            autoStartsRest: WorkoutPreferences.autoStartsRest(),
            rest: restTimer,
            languageCode: locale.language.languageCode?.identifier == "tr" ? "tr" : "en",
            decimalSeparator: locale.decimalSeparator ?? "."
        ) {
            let context = ModelContext(modelContainer)
            var entries = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map {
                ActiveWorkoutModel.CatalogEntry(item: ExerciseListItem($0), pattern: $0.movementPattern, mechanic: $0.mechanic)
            }
            let own = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil })
            entries += ((try? context.fetch(own)) ?? []).map {
                ActiveWorkoutModel.CatalogEntry(item: ExerciseListItem($0), pattern: nil, mechanic: nil)
            }
            return entries
        }
        let coordinator = LiveActivityCoordinator(
            session: session, rest: restTimer, service: ActivityKitLiveActivityService(),
            fallbackName: String(localized: "liveactivity.workout.fallback"),
            exerciseName: { [weak model] ref in model?.name(of: ref) ?? "" },
            isEnabled: { WorkoutPreferences.showsLiveActivity() }
        )
        liveActivity = coordinator
        Task { await coordinator.start() }
        return model
    }

    /// The summary screen of a just-finished workout (P041): numbers from DataKit plus the previous comparable
    /// workout and the muscles of each exercise. nil without a local store.
    func makeSummaryModel(
        workout: WorkoutSnapshot, records: [PersonalRecordHit], names: [ExerciseRef: String], unit: WeightUnit,
        decimalSeparator: String
    ) async -> WorkoutSummaryModel? {
        guard let modelContainer else { return nil }
        let repository = SwiftDataWorkoutRepository(modelContainer: modelContainer)
        let earlier = (try? await repository.finishedWorkouts(userId: workout.userId, before: workout.startedAt, limit: 40)) ?? []
        let summary = WorkoutSummary(
            workout: workout, previous: WorkoutSummary.previousComparable(to: workout, among: earlier),
            muscles: Self.muscles(of: workout, in: modelContainer), records: records
        )
        return WorkoutSummaryModel(
            workout: workout, summary: summary, unit: unit, names: names, repository: repository,
            decimalSeparator: decimalSeparator
        )
    }

    /// Muscles of the workout's catalog and custom exercises.
    private static func muscles(of workout: WorkoutSnapshot, in container: ModelContainer) -> [ExerciseRef: ExerciseMuscles] {
        let context = ModelContext(container)
        var result: [ExerciseRef: ExerciseMuscles] = [:]
        for exercise in workout.exercises {
            switch exercise.ref {
            case .catalog(let id):
                var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let row = (try? context.fetch(descriptor))?.first {
                    result[exercise.ref] = ExerciseMuscles(primary: row.primaryMuscles, secondary: row.secondaryMuscles)
                }
            case .custom(let id):
                var descriptor = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let row = (try? context.fetch(descriptor))?.first {
                    result[exercise.ref] = ExerciseMuscles(primary: row.primaryMuscles, secondary: row.secondaryMuscles)
                }
            }
        }
        return result
    }

    /// Everything the history screens need (P042): repositories, the editor that keeps records true, the display unit
    /// and the exercise names; nil without a user or local store.
    func makeHistoryContext() async -> HistoryContext? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        let profile = try? await SwiftDataProfileRepository(modelContainer: modelContainer).profile(userId: user.id)
        let locale = language.effectiveLocale()
        let languageCode = locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
        let workouts = SwiftDataWorkoutRepository(modelContainer: modelContainer)
        let records = SwiftDataPersonalRecordService(modelContainer: modelContainer)
        let userId = user.id
        return HistoryContext(
            userId: userId, workouts: workouts,
            editor: WorkoutHistoryEditor(
                userId: userId, workouts: workouts, records: records,
                health: WorkoutHealthRecorder(workouts: workouts, health: health)
            ),
            routines: SwiftDataRoutineRepository(modelContainer: modelContainer), records: records,
            unit: profile?.input.unitSystem == .imperial ? .pounds : .kilograms, locale: locale, languageCode: languageCode
        ) {
            let context = ModelContext(modelContainer)
            var names: [String: String] = [:]
            for row in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
                let item = ExerciseListItem(row)
                names[item.id] = item.name(languageCode: languageCode)
            }
            let own = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.userId == userId && $0.deletedAt == nil })
            for row in (try? context.fetch(own)) ?? [] {
                let item = ExerciseListItem(row)
                names[item.id] = item.name(languageCode: languageCode)
            }
            return names
        }
    }

    /// Keeps Apple Health and the local workouts in step (P041); nil without a local store.
    func workoutHealthRecorder() -> WorkoutHealthRecorder? {
        modelContainer.map { WorkoutHealthRecorder(workouts: SwiftDataWorkoutRepository(modelContainer: $0), health: health) }
    }

    private func planStore(for userId: UUID) -> RoutinePlanStore {
        if let existing = planStores[userId] { return existing }
        let store = RoutinePlanStore(userId: userId)
        planStores[userId] = store
        return store
    }

    func makeAccountModel(userId: UUID) -> AccountModel {
        AccountModel(
            userId: userId,
            service: accountService,
            confirmationWord: DeleteConfirmation.word(for: language.effectiveLocale())
        ) { [weak self] in await self?.signOut() }
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
                accountService: FakeAccountService(), modelContainer: store, health: uiTestHealth(),
                catalog: store.map { CatalogService(modelContainer: $0) }
            )
        }
        #endif
        let info = bundle.infoDictionary ?? [:]
        let store = makeStore(appGroupID: info["AppGroupID"] as? String)
        guard let config = SupabaseConfiguration(
            infoDictionary: info, urlScheme: info["AppURLScheme"] as? String
        ) else {
            Log.app.error("Supabase is not configured; running signed out. See docs/KURULUM.md.")
            return AppContainer(
                sessionService: PlaceholderSessionService(), modelContainer: store,
                catalog: store.map { CatalogService(modelContainer: $0) }
            )
        }
        let apple = AppleIDTokenProvider()
        let auth = SupabaseAuthService(configuration: config, apple: apple, google: GoogleIDTokenProvider())
        let accessToken: SupabaseRemoteStore.AccessToken = { await auth.accessToken() }
        // Apple users confirm once more with Apple so the server can revoke their Sign in with Apple tokens.
        let appleCode: @Sendable () async -> String? = {
            guard await auth.hasAppleIdentity() else { return nil }
            return try? await apple.credential().authorizationCode
        }
        let account = SupabaseAccountService(configuration: config, accessToken: accessToken, appleAuthorizationCode: appleCode)
        let remote = SupabaseRemoteStore(configuration: config, accessToken: accessToken)
        return AppContainer(
            sessionService: AuthSessionService(auth: auth), authService: auth, accountService: account, modelContainer: store,
            health: HealthKitService(),
            catalog: store.map { CatalogService(modelContainer: $0, remote: SupabaseCatalogRemote(configuration: config)) },
            exerciseImageBaseURL: config.url.appendingPathComponent("storage/v1/object/public/exercise-images"),
            sync: store.map { makeSync(store: $0, appGroupID: info["AppGroupID"] as? String, remote: remote) }
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
