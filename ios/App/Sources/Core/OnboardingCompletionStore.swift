import Foundation

/// Per-user, on-device record that onboarding was finished. Written first so a cold start works offline,
/// and re-synced to the server (`user_metadata.onboarding_complete`) when that write failed.
protocol OnboardingCompletionStore: Sendable {
    func isComplete(userId: UUID) -> Bool
    func markComplete(userId: UUID)
}

struct UserDefaultsOnboardingCompletionStore: OnboardingCompletionStore {
    private let suiteName: String?

    init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    private func key(_ userId: UUID) -> String { "onboarding.complete.\(userId.uuidString)" }

    func isComplete(userId: UUID) -> Bool { defaults.bool(forKey: key(userId)) }
    func markComplete(userId: UUID) { defaults.set(true, forKey: key(userId)) }
}
