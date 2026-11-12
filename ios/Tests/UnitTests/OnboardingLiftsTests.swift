import DataKit
import Foundation
import StrengthKit
import Testing

@testable import ATROX

/// Onboarding part 3 — first strength profile (P021). Shares the harness of the part 1 tests.
@MainActor
struct OnboardingLiftsTests {
    private typealias Base = OnboardingViewModelTests

    /// Walks a fresh model through all earlier steps to the lifts screen.
    private static func atLifts(
        _ env: Base.Harness, equipment: EquipmentAccess = .fullGym, unit: UnitSystem = .metric
    ) async {
        env.model.firstName = "Ada"
        await env.model.advance()
        env.model.setBirthDate(Base.date(1995, 3, 2))
        await env.model.advance()
        env.model.setSex(.male)
        await env.model.advance()
        env.model.setUnitSystem(unit)
        await env.model.advance()
        env.model.setWeight(kg: 80)
        await env.model.advance()
        env.model.setExperience(.twoToFiveYears)
        await env.model.advance()
        env.model.setGoal(.muscleGain)
        await env.model.advance()
        await env.model.advance()
        env.model.setEquipment(equipment)
        await env.model.advance()
        env.model.toggleNoLimitations()
        await env.model.advance()
        await env.model.acceptLegal()
        await env.model.decideContribution(false)
    }

    @Test func consentsLeadToTheLiftsStep() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        #expect(env.model.step == .lifts)
        #expect(env.model.liftEntries.map(\.lift) == [.benchPress, .squat, .deadlift, .overheadPress])
        #expect(env.model.canAdvance && !env.model.canGoBack)
    }

    @Test func skippingEverythingStillReachesAnEmptyResult() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        for lift in OnboardingLifts.order { env.model.setLiftSkipped(lift, true) }
        await env.model.advance()
        #expect(env.model.step == .result)
        #expect(env.model.results.isEmpty)
        #expect(env.setStore.load(userId: env.userId).isEmpty)
    }

    @Test func advancingWithoutTypingAnythingIsTheSameAsSkipping() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        await env.model.advance()
        #expect(env.model.step == .result)
        #expect(env.model.results.isEmpty)
    }

    @Test func aSetGivesAScoreAndIsStored() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        env.model.setLiftWeight(.benchPress, value: 80)
        env.model.setLiftReps(.benchPress, reps: 1)
        env.model.setLiftSkipped(.squat, true)
        await env.model.advance()
        #expect(env.model.step == .result)
        let result = try #require(env.model.results.first)
        #expect(env.model.results.count == 1 && result.lift == .benchPress)
        #expect(abs(result.score - 50) < 1e-9)  // 1.0 x bodyweight against the placeholder's 2.0
        let stored = env.setStore.load(userId: env.userId)
        #expect(stored == [LiftSet(lift: .benchPress, implement: .barbell, weightKg: 80, reps: 1)])
    }

    @Test func unfinishedCardsAreIgnored() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        env.model.setLiftWeight(.squat, value: 100)
        env.model.setLiftSkipped(.squat, true)  // typed, then skipped
        env.model.setLiftWeight(.deadlift, value: nil)
        env.model.setLiftWeight(.overheadPress, value: -5)
        #expect(env.model.reportedSets.isEmpty)
    }

    @Test func poundsAreConvertedToKilograms() async throws {
        let env = try Base.harness()
        await Self.atLifts(env, unit: .imperial)
        #expect(env.model.weightUnit == .pounds)
        env.model.setLiftWeight(.benchPress, value: 220)
        let kg = try #require(env.model.entry(for: .benchPress).weightKg)
        #expect(abs(kg - 99.79) < 0.01)
    }

    @Test func absurdWeightsAndRepsAreClamped() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        env.model.setLiftWeight(.benchPress, value: 9_999)
        env.model.setLiftReps(.benchPress, reps: 500)
        #expect(env.model.entry(for: .benchPress).weightKg == OnboardingLifts.maximumWeightKg)
        #expect(env.model.entry(for: .benchPress).reps == OnboardingLifts.repsRange.upperBound)
        env.model.setLiftReps(.benchPress, reps: 0)
        #expect(env.model.entry(for: .benchPress).reps == 1)
    }

    @Test func equipmentPicksTheImplement() {
        #expect(OnboardingLifts.implement(for: .fullGym) == .barbell)
        #expect(OnboardingLifts.implement(for: .homeBarbell) == .barbell)
        #expect(OnboardingLifts.implement(for: .homeDumbbell) == .dumbbell)
        #expect(OnboardingLifts.implement(for: .bodyweightOnly) == .dumbbell)
    }

    @Test func dumbbellUsersGetDumbbellSets() async throws {
        let env = try Base.harness()
        await Self.atLifts(env, equipment: .homeDumbbell)
        env.model.setLiftWeight(.benchPress, value: 30)
        #expect(env.model.reportedSets.first?.implement == .dumbbell)
        #expect(env.model.results.count == 1)
    }

    @Test func goingBackFromTheResultKeepsTheEnteredSets() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        env.model.setLiftWeight(.squat, value: 100)
        await env.model.advance()
        env.model.back()
        #expect(env.model.step == .lifts)
        #expect(env.model.entry(for: .squat).weightKg == 100)
    }

    @Test func enteredSetsSurviveARelaunch() async throws {
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-lifts-\(UUID().uuidString)")!
        let first = try Base.harness(userId: userId, defaults: defaults)
        await Self.atLifts(first)
        first.model.setLiftWeight(.deadlift, value: 140)
        let second = try Base.harness(userId: userId, defaults: defaults)
        #expect(second.model.step == .lifts)
        #expect(second.model.entry(for: .deadlift).weightKg == 140)
    }

    @Test func finishingClearsTheDraft() async throws {
        let env = try Base.harness()
        await Self.atLifts(env)
        await env.model.advance()
        env.model.finish()
        #expect(env.store.load(userId: env.userId) == nil)
    }

    @Test func aDraftSavedBeforeTheLiftsExistedStillLoads() throws {
        // Raw value 12 was `trainingDone` before P021, and such drafts have no `lifts` key at all.
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-legacy-lifts-\(UUID().uuidString)")!
        var draft = OnboardingDraft()
        draft.step = try #require(OnboardingStep(rawValue: 12))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        json.removeValue(forKey: "lifts")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "onboarding.draft.\(userId.uuidString)")
        let env = try Base.harness(userId: userId, defaults: defaults)
        #expect(env.model.step == .lifts)
        #expect(env.model.liftEntries.count == 4)
    }

    @Test func liftStepsAreNotQuestions() {
        #expect(!OnboardingStep.questions.contains(.lifts))
        #expect(OnboardingStep.lifts.rawValue < OnboardingStep.result.rawValue)
    }
}
