import DataKit
import Foundation

/// Steps of onboarding part 1 (P018). One question per step. Raw values are persisted in the draft.
enum OnboardingStep: Int, CaseIterable, Codable, Sendable {
    case name, birthDate, sex, units, body
    /// Part 1 is saved; the next parts (P019+) continue from here.
    case partOneDone

    /// Question steps only (the progress bar counts these).
    static let questions: [OnboardingStep] = [.name, .birthDate, .sex, .units, .body]
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
