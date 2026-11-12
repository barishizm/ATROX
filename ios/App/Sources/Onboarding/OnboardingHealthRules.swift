import Foundation

/// Cleans up what Health returned so only values the onboarding would accept are proposed.
enum OnboardingHealthRules {
    static func sanitized(_ profile: HealthBodyProfile, now: Date, calendar: Calendar) -> HealthBodyProfile {
        var result = HealthBodyProfile()
        // The wheels move in 1 cm / 0.5 kg steps; propose a value the wheel can show.
        if let height = profile.heightCm.map({ $0.rounded() }), OnboardingRules.isValidHeight(cm: height) {
            result.heightCm = height
        }
        if let weight = profile.weightKg.map({ ($0 * 2).rounded() / 2 }), OnboardingRules.isValidWeight(kg: weight) {
            result.weightKg = weight
        }
        if let birthDate = profile.birthDate,
           OnboardingRules.checkBirthDate(birthDate, now: now, calendar: calendar) == .valid {
            result.birthDate = birthDate
        }
        result.sex = profile.sex
        return result
    }
}
