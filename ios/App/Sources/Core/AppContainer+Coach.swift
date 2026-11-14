import CoachKit
import DataKit
import DesignSystem
import Foundation

/// Coach wiring of the composition root (P079/P080).
extension AppContainer {
    /// Production: the `coach-chat` Edge Function over SSE and the user's coach tables over PostgREST, with the
    /// conversation cache next to the app's other support files.
    static func makeCoach(
        config: SupabaseConfiguration, accessToken: @escaping @Sendable () async -> String?,
        refreshedToken: @escaping @Sendable () async -> String?
    ) -> CoachDependencies {
        let chat = SupabaseCoachChatService(
            baseURL: config.url, anonKey: config.anonKey, accessToken: accessToken, refreshedToken: refreshedToken
        )
        let remote = SupabaseCoachRemote(baseURL: config.url, anonKey: config.anonKey, accessToken: accessToken)
        let directory = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let cache = FileCoachCache(url: directory.appendingPathComponent("Coach/conversations.json"))
        let digest = SupabaseCoachDigestService(
            baseURL: config.url, anonKey: config.anonKey, accessToken: accessToken, refreshedToken: refreshedToken
        )
        return CoachDependencies(chat: chat, repository: CoachRepository(remote: remote, cache: cache), digest: digest)
    }

    #if DEBUG
    /// `-uitest-fake-coach`: a scripted coach (no network) and an in-memory conversation store.
    static func uiTestCoach() -> CoachDependencies? {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-fake-coach") else { return nil }
        return CoachDependencies(
            chat: ScriptedCoachService(), repository: CoachRepository(remote: EmptyCoachRemote(), cache: InMemoryCoachCache())
        )
    }
    #else
    static func uiTestCoach() -> CoachDependencies? { nil }
    #endif

    /// The user's AI-sharing decision (P081); nil without a local store or a user. One per user.
    func coachConsent() async -> CoachConsentModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        if let existing = coachConsentState, existing.userId == user.id { return existing }
        let model = CoachConsentModel(
            service: ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer)), userId: user.id
        )
        coachConsentState = model
        await model.load()
        return model
    }

    /// The coach tab's model; nil without Supabase (no coach) or without a user / local store.
    /// Every turn is checked against the stored consent first: without it the coach endpoint is never called.
    func makeCoachModel() async -> CoachModel? {
        guard let coach, let modelContainer, let user = await currentUser() else { return nil }
        let consents = ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer))
        let gated = ConsentGatedChatService(coach.chat, requiredVersion: ConsentVersions.current.aiSharing) {
            (try? await consents.isAISharingGranted(userId: user.id)) ?? false
        }
        let locale = language.effectiveLocale()
        let plan = planStore(for: user.id)
        let routines = SwiftDataRoutineRepository(modelContainer: modelContainer)
        let applier = ProposalApplier(
            userId: user.id, routines: routines, profiles: SwiftDataProfileRepository(modelContainer: modelContainer),
            activeRoutineId: { plan.activeRoutineId }, activate: { plan.setActive($0) }
        )
        let session = CoachSession(
            service: gated, locale: { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" },
            decisionSink: { [repository = coach.repository] id, decision in
                await repository.recordDecision(proposalID: id, decision: decision)
            }
        )
        let workouts = SwiftDataWorkoutRepository(modelContainer: modelContainer)
        let userId = user.id
        return CoachModel(session: session, repository: coach.repository, applier: applier, locale: locale) { [weak self] in
            var facts = CoachSuggestions.Facts()
            if let center = await self?.scoreCenter(), let muscles = center.overview?.muscles {
                facts.weakestMuscle = muscles.min { $0.value.score < $1.value.score }?.key
            }
            facts.hasWorkouts = ((try? await workouts.finishedWorkouts(userId: userId, before: nil, limit: 1)) ?? []).isEmpty == false
            facts.hasRoutine = plan.activeRoutineId != nil
            return facts
        }
    }

    /// Proactive comments (P083) for the signed-in user; nil without a local store or a user. The consent is read at
    /// every request, so withdrawing it in Settings stops the next comment at once.
    func makeCommentProvider() async -> CoachCommentProvider? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        let consents = ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer))
        let userId = user.id
        return CoachCommentProvider(digest: coach?.digest) { (try? await consents.isAISharingGranted(userId: userId)) ?? false }
    }

    /// "Ask the coach" entry points (insight cards, exercise screens): the tab opens with the text in the input.
    func askCoach(_ prompt: String) {
        pendingCoachPrompt = prompt
        requestedTab = .coach
    }
}
