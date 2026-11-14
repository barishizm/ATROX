import Foundation

/// The closed vocabulary of product analytics events (P100, docs/ANALITIK.md).
///
/// Privacy by construction: an event is a name plus parameters whose values are *categories* from fixed enums.
/// There is no case that takes a free string, a number such as weight or score, or message text, so no call site
/// can leak personal data. Adding an event means adding a case here and a row to docs/ANALITIK.md.
public enum AnalyticsEvent: Sendable, Equatable {
    // Funnel: install → sign-up → onboarding → first workout → first score → day-7 return
    case signUpCompleted(method: SignInMethod)
    case onboardingCompleted
    case firstWorkoutFinished
    case firstScoreViewed
    case day7Return

    // Feature use
    case coachMessageSent
    case coachSuggestionDecided(CoachDecision)
    case shareCompleted(target: ShareTarget)
    case referenceGroupChanged(group: ReferenceGroup)

    // Revenue
    case paywallViewed(source: PaywallSource)
    case trialStarted(plan: SubscriptionPlan)
    case subscriptionStarted(plan: SubscriptionPlan)

    public enum SignInMethod: String, Sendable, CaseIterable { case apple, google, email }
    public enum CoachDecision: String, Sendable, CaseIterable { case applied, rejected }
    public enum ShareTarget: String, Sendable, CaseIterable { case instagramStories, shareSheet, saveImage }
    public enum ReferenceGroup: String, Sendable, CaseIterable { case gym, general, competitor }
    public enum PaywallSource: String, Sendable, CaseIterable { case coach, scores, history, settings, onboarding, other }
    public enum SubscriptionPlan: String, Sendable, CaseIterable { case monthly, yearly }

    /// Stable wire name, `atrox.<area>.<action>`.
    public var name: String {
        switch self {
        case .signUpCompleted: "atrox.funnel.signUpCompleted"
        case .onboardingCompleted: "atrox.funnel.onboardingCompleted"
        case .firstWorkoutFinished: "atrox.funnel.firstWorkoutFinished"
        case .firstScoreViewed: "atrox.funnel.firstScoreViewed"
        case .day7Return: "atrox.funnel.day7Return"
        case .coachMessageSent: "atrox.coach.messageSent"
        case .coachSuggestionDecided: "atrox.coach.suggestionDecided"
        case .shareCompleted: "atrox.share.completed"
        case .referenceGroupChanged: "atrox.scores.referenceGroupChanged"
        case .paywallViewed: "atrox.revenue.paywallViewed"
        case .trialStarted: "atrox.revenue.trialStarted"
        case .subscriptionStarted: "atrox.revenue.subscriptionStarted"
        }
    }

    /// Category parameters only (values come from the enums above).
    public var parameters: [String: String] {
        switch self {
        case .signUpCompleted(let method): ["method": method.rawValue]
        case .coachSuggestionDecided(let decision): ["decision": decision.rawValue]
        case .shareCompleted(let target): ["target": target.rawValue]
        case .referenceGroupChanged(let group): ["group": group.rawValue]
        case .paywallViewed(let source): ["source": source.rawValue]
        case .trialStarted(let plan), .subscriptionStarted(let plan): ["plan": plan.rawValue]
        case .onboardingCompleted, .firstWorkoutFinished, .firstScoreViewed, .day7Return,
             .coachMessageSent: [:]
        }
    }

    /// Funnel milestones fire at most once per install.
    public var isOncePerInstall: Bool {
        switch self {
        case .signUpCompleted, .onboardingCompleted, .firstWorkoutFinished, .firstScoreViewed, .day7Return: true
        default: false
        }
    }
}
