import DataKit
import Foundation
import Testing

@testable import ATROX

/// Onboarding part 2 — training profile (P019). Shares the harness of the part 1 tests.
@MainActor
struct OnboardingTrainingTests {
    private typealias Base = OnboardingViewModelTests

    /// Walks a fresh model to the experience question.
    private static func atExperience(_ env: Base.Harness) async {
        env.model.firstName = "Ada"
        await env.model.advance()
        env.model.setBirthDate(Base.date(1995, 3, 2))
        for _ in 0..<4 { await env.model.advance() }
    }

    @Test func tenQuestionsInTotalAndProgressReachesTheEnd() {
        #expect(OnboardingStep.questions.count == 10)
        #expect(OnboardingStep.questions.first == .name && OnboardingStep.questions.last == .limitations)
    }

    @Test func eachTrainingQuestionNeedsAnAnswerExceptFrequency() async throws {
        let env = try Base.harness()
        await Self.atExperience(env)
        #expect(env.model.step == .experience)
        #expect(!env.model.canAdvance)
        env.model.setExperience(.twoToFiveYears)
        #expect(env.model.canAdvance)
        await env.model.advance()
        #expect(env.model.step == .goal)
        #expect(!env.model.canAdvance)
        env.model.setGoal(.muscleGain)
        await env.model.advance()
        #expect(env.model.step == .frequency)
        #expect(env.model.canAdvance)  // defaults to 3
        await env.model.advance()
        #expect(env.model.step == .equipment)
        #expect(!env.model.canAdvance)
        env.model.setEquipment(.homeDumbbell)
        await env.model.advance()
        #expect(env.model.step == .limitations)
        #expect(!env.model.canAdvance)
    }

    @Test func weeklyFrequencyIsClampedToOneThroughSeven() throws {
        let env = try Base.harness()
        env.model.setWeeklyFrequency(0)
        #expect(env.model.draft.weeklyFrequency == 1)
        env.model.setWeeklyFrequency(9)
        #expect(env.model.draft.weeklyFrequency == 7)
        env.model.setWeeklyFrequency(4)
        #expect(env.model.draft.weeklyFrequency == 4)
    }

    @Test func noLimitationsExcludesAreasAndNote() throws {
        let env = try Base.harness()
        env.model.toggleLimitation(.knee)
        env.model.limitationNote = "old injury"
        env.model.toggleNoLimitations()
        #expect(env.model.draft.noLimitations)
        #expect(env.model.draft.limitations.isEmpty)
        #expect(env.model.limitationNote.isEmpty)
        env.model.toggleLimitation(.shoulder)  // picking an area clears "none"
        #expect(!env.model.draft.noLimitations)
        env.model.toggleLimitation(.shoulder)  // and toggles off again
        #expect(env.model.draft.limitations.isEmpty)
    }

    @Test func limitationNoteIsCapped() throws {
        let env = try Base.harness()
        env.model.limitationNote = String(repeating: "x", count: 500)
        #expect(env.model.limitationNote.count == LimitationCodec.noteLimit)
    }

    @Test func finishingWritesTrainingProfileToTheStore() async throws {
        let env = try Base.harness()
        await Self.atExperience(env)
        env.model.setExperience(.sixMonthsToTwoYears)
        await env.model.advance()
        env.model.setGoal(.fatLoss)
        await env.model.advance()
        env.model.setWeeklyFrequency(5)
        await env.model.advance()
        env.model.setEquipment(.homeBarbell)
        await env.model.advance()
        env.model.toggleLimitation(.lowerBack)
        env.model.toggleLimitation(.wrist)
        env.model.limitationNote = "  disc issue  "
        await env.model.advance()

        #expect(env.model.step == .terms)  // consents come next (P020)
        let profile = try #require(try await env.profiles.profile(userId: env.userId)).input
        #expect(profile.experience == .sixMonthsToTwoYears)
        #expect(profile.goal == .fatLoss)
        #expect(profile.weeklyFrequency == 5)
        #expect(profile.equipmentAccess == .homeBarbell)
        #expect(profile.firstName == "Ada")  // identity kept
        let decoded = LimitationCodec.decode(profile.limitations)
        #expect(decoded.areas == [.lowerBack, .wrist])  // catalog order, not tap order
        #expect(decoded.note == "disc issue")
        #expect(try await env.measurements.all(userId: env.userId).count == 1)
    }

    @Test func noLimitationsSavesAnEmptyList() async throws {
        let env = try Base.harness()
        await Self.atExperience(env)
        env.model.setExperience(.noExperience)
        await env.model.advance()
        env.model.setGoal(.generalHealth)
        await env.model.advance()
        await env.model.advance()
        env.model.setEquipment(.bodyweightOnly)
        await env.model.advance()
        env.model.toggleNoLimitations()
        await env.model.advance()
        #expect(try await env.profiles.profile(userId: env.userId)?.input.limitations == [])
        #expect(try await env.profiles.profile(userId: env.userId)?.input.weeklyFrequency == 3)
    }

    @Test func resumesInTheMiddleOfPartTwo() async throws {
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-resume2-\(UUID().uuidString)")!
        let first = try Base.harness(userId: userId, defaults: defaults)
        await Self.atExperience(first)
        first.model.setExperience(.over5Years)
        await first.model.advance()
        first.model.setGoal(.strength)
        await first.model.advance()
        first.model.setWeeklyFrequency(6)
        await first.model.advance()

        let second = try Base.harness(userId: userId, defaults: defaults)
        #expect(second.model.step == .equipment)
        #expect(second.model.draft.experience == .over5Years)
        #expect(second.model.draft.goal == .strength)
        #expect(second.model.draft.weeklyFrequency == 6)
        second.model.back()
        #expect(second.model.step == .frequency)
    }

    @Test func limitationCodecRoundTripsAndIgnoresUnknownEntries() {
        let stored = LimitationCodec.encode([.hip, .shoulder], note: " careful ")
        #expect(stored == ["shoulder", "hip", "note:careful"])
        let decoded = LimitationCodec.decode(stored + ["future_area"])
        #expect(decoded.areas == [.shoulder, .hip])
        #expect(decoded.note == "careful")
        #expect(LimitationCodec.encode([], note: "  ").isEmpty)
    }
}
