import DataKit
import Foundation
import Testing

@testable import GymAnalyzer

/// Onboarding consent screens (P020): terms + privacy, then the opt-in model contribution.
@MainActor
struct OnboardingConsentTests {
    private typealias Base = OnboardingViewModelTests

    /// Walks a fresh model through every question to the terms screen.
    private static func atTerms(_ env: Base.Harness) async {
        env.model.firstName = "Ada"
        await env.model.advance()
        env.model.setBirthDate(Base.date(1995, 3, 2))
        for _ in 0..<4 { await env.model.advance() }
        env.model.setExperience(.twoToFiveYears)
        await env.model.advance()
        env.model.setGoal(.strength)
        await env.model.advance()
        await env.model.advance()
        env.model.setEquipment(.fullGym)
        await env.model.advance()
        env.model.toggleNoLimitations()
        await env.model.advance()
    }

    private func current(_ env: Base.Harness, _ kind: ConsentKind) async throws -> ConsentSnapshot? {
        try await env.consentRepository.current(kind: kind, userId: env.userId)
    }

    @Test func termsComeAfterTheQuestionsAndHaveNoNextButton() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        #expect(env.model.step == .terms)
        #expect(!env.model.canAdvance)  // only "I agree and continue" moves on
        #expect(env.model.progress == 1)
        #expect(env.model.canGoBack)
        #expect(try await current(env, .terms) == nil)  // nothing is recorded by merely arriving
    }

    @Test func acceptingRecordsTermsAndPrivacyWithVersions() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        await env.model.acceptLegal()
        #expect(env.model.step == .contribution)
        let terms = try #require(try await current(env, .terms))
        let privacy = try #require(try await current(env, .privacy))
        #expect(terms.granted && privacy.granted)
        #expect(terms.version == ConsentVersions.current.terms)
        #expect(privacy.version == ConsentVersions.current.privacy)
        #expect(try await current(env, .mlContribution) == nil)  // still unanswered, never pre-granted
    }

    @Test func contributingStoresAGrantAndFinishes() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        await env.model.acceptLegal()
        await env.model.decideContribution(true)
        #expect(env.model.step == .trainingDone)
        let row = try #require(try await current(env, .mlContribution))
        #expect(row.granted && row.version == ConsentVersions.current.mlContribution)
    }

    @Test func notNowStoresAnExplicitNoAndFinishes() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        await env.model.acceptLegal()
        await env.model.decideContribution(false)
        #expect(env.model.step == .trainingDone)
        let row = try #require(try await current(env, .mlContribution))
        #expect(!row.granted)
    }

    @Test func consentAnswersAreIgnoredOnTheWrongStep() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        await env.model.decideContribution(true)  // still on terms
        #expect(env.model.step == .terms)
        #expect(try await current(env, .mlContribution) == nil)
    }

    @Test func goingBackAndAcceptingAgainDoesNotDuplicateRows() async throws {
        let env = try Base.harness()
        await Self.atTerms(env)
        await env.model.acceptLegal()
        env.model.back()
        #expect(env.model.step == .terms)
        await env.model.acceptLegal()
        #expect(try await env.consentRepository.history(userId: env.userId).count == 2)
    }

    @Test func resumesOnTheContributionScreenAfterRelaunch() async throws {
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-consent-\(UUID().uuidString)")!
        let first = try Base.harness(userId: userId, defaults: defaults)
        await Self.atTerms(first)
        await first.model.acceptLegal()
        let second = try Base.harness(userId: userId, defaults: defaults)
        #expect(second.model.step == .contribution)
    }

    @Test func aDraftSavedAtTheOldFinalStepResumesAtTerms() throws {
        // Raw value 10 was `trainingDone` before P020; people parked there still owe the consents.
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-legacy-\(UUID().uuidString)")!
        var draft = OnboardingDraft()
        draft.step = try #require(OnboardingStep(rawValue: 10))
        UserDefaultsOnboardingDraftStore(defaults: defaults).save(draft, userId: userId)
        let env = try Base.harness(userId: userId, defaults: defaults)
        #expect(env.model.step == .terms)
    }

    @Test func consentStepsAreNotQuestions() {
        #expect(!OnboardingStep.questions.contains(.terms))
        #expect(!OnboardingStep.questions.contains(.contribution))
        #expect(OnboardingStep.terms.rawValue < OnboardingStep.contribution.rawValue)
        #expect(OnboardingStep.contribution.rawValue < OnboardingStep.trainingDone.rawValue)
    }
}
