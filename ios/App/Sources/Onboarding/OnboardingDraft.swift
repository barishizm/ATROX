import DataKit
import Foundation
import StrengthKit

/// Steps of onboarding parts 1–3 (P018–P021). One question per step. Raw values are persisted in the draft,
/// so never reorder: new steps go before `result`. (Raw value 5 was P018's interim "part one done"
/// screen; a draft saved there now resumes at the experience question. Raw value 10 was `trainingDone` before
/// the consent steps existed; such a draft now resumes at `terms`, which is where that user has to continue.
/// Raw value 12 was `trainingDone` before the lifts existed; such a draft now resumes at `lifts`.)
enum OnboardingStep: Int, CaseIterable, Codable, Sendable {
    case name, birthDate, sex, units, body
    case experience, goal, frequency, equipment, limitations
    /// Consent screens (P020): terms + privacy, then the optional model-contribution question.
    case terms, contribution
    /// First strength profile (P021): best sets of the four basic lifts, then the first scores.
    case lifts, result

    /// Question steps only (the progress bar counts these).
    static let questions: [OnboardingStep] = [
        .name, .birthDate, .sex, .units, .body, .experience, .goal, .frequency, .equipment, .limitations,
    ]
}

/// What the user has entered so far. Saved after every step so a killed app resumes where it stopped.
/// `birthDate` is never stored for an under-16 user (see `OnboardingViewModel`).
struct OnboardingDraft: Codable, Equatable, Sendable {
    var step: OnboardingStep = .name
    var firstName = ""
    var lastName = ""
    var birthDate: Date?
    var sex: Sex = .unspecified
    var unitSystem: UnitSystem = .metric
    var heightCm: Double = OnboardingRules.defaultHeightCm
    var weightKg: Double = OnboardingRules.defaultWeightKg
    // Part 2 (training profile). `nil` = not answered yet.
    var experience: Experience?
    var goal: Goal?
    var weeklyFrequency: Int = OnboardingRules.defaultWeeklyFrequency
    var equipment: EquipmentAccess?
    var limitations: [BodyLimitation] = []
    /// "No limitations" was chosen explicitly (mutually exclusive with `limitations`).
    var noLimitations = false
    var limitationNote = ""
    // Part 3 (first strength profile). `nil` = the step has not been opened yet (also: drafts saved before P021).
    var lifts: [LiftEntry]?
}

/// Persistence for the draft, keyed by user so two accounts on one device never mix.
protocol OnboardingDraftStore: Sendable {
    func load(userId: UUID) -> OnboardingDraft?
    func save(_ draft: OnboardingDraft, userId: UUID)
    func clear(userId: UUID)
}

/// `UserDefaults` is documented as thread-safe, hence `@unchecked`.
struct UserDefaultsOnboardingDraftStore: OnboardingDraftStore, @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ userId: UUID) -> String { "onboarding.draft.\(userId.uuidString)" }

    func load(userId: UUID) -> OnboardingDraft? {
        guard let data = defaults.data(forKey: key(userId)) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func save(_ draft: OnboardingDraft, userId: UUID) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(userId))
    }

    func clear(userId: UUID) { defaults.removeObject(forKey: key(userId)) }
}
