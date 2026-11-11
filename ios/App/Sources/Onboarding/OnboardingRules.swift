import DataKit
import Foundation

/// Pure validation rules for onboarding part 1. Ranges mirror the DB CHECK constraints
/// (`profiles.height_cm` 100–250, `profiles.birth_date` ≥ 16 years, `body_measurements.weight_kg` 20–400).
enum OnboardingRules {
    static let minimumAge = 16
    static let maximumAge = 100
    static let nameLimit = 50
    static let heightRangeCm = 100.0...250.0
    static let weightRangeKg = 30.0...300.0
    static let defaultHeightCm = 170.0
    static let defaultWeightKg = 70.0
    static let weeklyFrequencyRange = 1...7
    static let defaultWeeklyFrequency = 3
    static let limitationNoteLimit = LimitationCodec.noteLimit

    enum BirthDateCheck: Equatable { case valid, tooYoung, implausible }

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func isValidFirstName(_ text: String) -> Bool {
        let name = trimmed(text)
        return !name.isEmpty && name.count <= nameLimit
    }

    static func isValidLastName(_ text: String) -> Bool { trimmed(text).count <= nameLimit }

    static func age(birthDate: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: now).year ?? 0
    }

    static func checkBirthDate(_ birthDate: Date, now: Date, calendar: Calendar) -> BirthDateCheck {
        guard birthDate <= now else { return .implausible }
        let years = age(birthDate: birthDate, now: now, calendar: calendar)
        if years < minimumAge { return .tooYoung }
        return years > maximumAge ? .implausible : .valid
    }

    /// A sensible starting point for the date wheel: 25 years ago.
    static func defaultBirthDate(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .year, value: -25, to: now) ?? now
    }

    static func isValidHeight(cm: Double) -> Bool { heightRangeCm.contains(cm) }
    static func isValidWeight(kg: Double) -> Bool { weightRangeKg.contains(kg) }

    /// Metric by default, imperial where the region uses it (US; same rule as `WeightUnit.default`).
    static func defaultUnitSystem(for locale: Locale) -> UnitSystem {
        locale.measurementSystem == .us ? .imperial : .metric
    }
}
