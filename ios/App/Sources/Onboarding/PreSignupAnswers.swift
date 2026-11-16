import DataKit
import DesignSystem
import Foundation

/// Muscle groups the user wants to prioritise (asked before sign-up). Stored on the device only for now;
/// the profile and the program recommendation do not read it yet.
enum FocusMuscle: String, Codable, CaseIterable, Sendable {
    case chest, legs, arms, abs

    /// Catalog muscles lit on the body diagram for this region.
    var catalogMuscles: [Muscle] {
        switch self {
        case .chest: [.chest]
        case .legs: [.quadriceps, .hamstrings, .adductors, .abductors, .calves]
        case .arms: [.biceps, .triceps, .forearms]
        case .abs: [.abdominals]
        }
    }
}

/// Answers to the plan questions asked *before* the account exists (`PlanQuizModel`). They live on the device,
/// survive an app restart during sign-up, and are consumed by `OnboardingViewModel` after the first sign-in:
/// it starts from `makeDraft()` instead of asking the same questions again.
/// A birth date under the minimum age is never stored.
struct PreSignupAnswers: Codable, Equatable, Sendable {
    /// Raw value of the quiz step to resume at.
    var step = 0
    var firstName = ""
    var sex: Sex?
    var unitSystem: UnitSystem = .metric
    var weightKg = OnboardingRules.defaultWeightKg
    var heightCm = OnboardingRules.defaultHeightCm
    var birthDate: Date?
    /// In the order picked; the first one is the primary goal.
    var goals: [Goal] = []
    var focusMuscles: [FocusMuscle] = []
    var experience: Experience?
    var equipment: EquipmentAccess?
    var weeklyFrequency = OnboardingRules.defaultWeeklyFrequency
    var limitations: [BodyLimitation] = []
    /// "No limitations" was chosen explicitly (exclusive with `limitations`).
    var noLimitations = false
    /// Terms and privacy policy were accepted in the quiz; recorded as consent after the first sign-in.
    var acceptedLegal = false
    /// Answer to the model-contribution question (nil = not asked yet); recorded after the first sign-in.
    var contribution: Bool?
    /// Every question was answered.
    var isComplete = false

    /// The onboarding draft these answers amount to, resuming at the first question that was not asked
    /// (physical limitations, shown prefilled for a last look). nil until the quiz is complete.
    func makeDraft() -> OnboardingDraft? {
        guard isComplete, let birthDate, let sex, let experience, let equipment, let goal = goals.first else { return nil }
        var draft = OnboardingDraft()
        draft.step = .limitations
        draft.firstName = firstName
        draft.birthDate = birthDate
        draft.sex = sex
        draft.unitSystem = unitSystem
        draft.heightCm = heightCm
        draft.weightKg = weightKg
        draft.experience = experience
        draft.goal = goal
        draft.weeklyFrequency = weeklyFrequency
        draft.equipment = equipment
        draft.limitations = limitations
        draft.noLimitations = noLimitations
        return draft
    }
}

/// Persistence for the pre-sign-up answers (one set per device: there is no user yet).
protocol PreSignupStore: Sendable {
    func load() -> PreSignupAnswers?
    func save(_ answers: PreSignupAnswers)
    func clear()
}

/// `UserDefaults` is documented as thread-safe, hence `@unchecked`.
struct UserDefaultsPreSignupStore: PreSignupStore {
    private let defaults: SendableDefaults
    private let key = "preSignup.answers"

    init(defaults: UserDefaults = .standard) { self.defaults = SendableDefaults(defaults) }

    func load() -> PreSignupAnswers? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PreSignupAnswers.self, from: data)
    }

    func save(_ answers: PreSignupAnswers) {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}
