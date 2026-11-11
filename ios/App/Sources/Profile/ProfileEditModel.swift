import DataKit
import Foundation
import Observation

/// Form state for "Edit profile": every onboarding answer except the unit system (that lives in Settings).
@MainActor
@Observable
final class ProfileEditModel {
    var firstName: String
    var lastName: String
    var birthDate: Date
    var sex: Sex
    var heightCm: Double
    var experience: Experience
    var goal: Goal
    var weeklyFrequency: Int
    var equipment: EquipmentAccess
    var limitations: [BodyLimitation]
    var limitationNote: String

    let unitSystem: UnitSystem
    private let base: ProfileInput
    private let now: () -> Date
    private let calendar: Calendar

    init(profile: ProfileInput, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        base = profile
        self.now = now
        self.calendar = calendar
        unitSystem = profile.unitSystem
        firstName = profile.firstName ?? ""
        lastName = profile.lastName ?? ""
        birthDate = profile.birthDate
        sex = profile.sex
        heightCm = profile.heightCm
        experience = profile.experience
        goal = profile.goal
        weeklyFrequency = profile.weeklyFrequency
        equipment = profile.equipmentAccess
        let decoded = LimitationCodec.decode(profile.limitations)
        limitations = decoded.areas
        limitationNote = decoded.note
    }

    var birthDateRange: ClosedRange<Date> {
        let today = now()
        let oldest = calendar.date(byAdding: .year, value: -(OnboardingRules.maximumAge + 1), to: today) ?? today
        return oldest...today
    }

    var birthDateCheck: OnboardingRules.BirthDateCheck {
        OnboardingRules.checkBirthDate(birthDate, now: now(), calendar: calendar)
    }

    var canSave: Bool {
        OnboardingRules.isValidFirstName(firstName) && OnboardingRules.isValidLastName(lastName)
            && birthDateCheck == .valid && OnboardingRules.isValidHeight(cm: heightCm)
            && OnboardingRules.weeklyFrequencyRange.contains(weeklyFrequency)
    }

    var hasChanges: Bool { input() != base }

    func toggle(_ area: BodyLimitation) {
        if let index = limitations.firstIndex(of: area) {
            limitations.remove(at: index)
        } else {
            limitations.append(area)
        }
    }

    func setNote(_ text: String) { limitationNote = String(text.prefix(OnboardingRules.limitationNoteLimit)) }

    /// The profile as edited; fields this form does not own (units, locale) are carried over.
    func input() -> ProfileInput {
        var result = base
        let first = OnboardingRules.trimmed(firstName)
        let last = OnboardingRules.trimmed(lastName)
        result.firstName = first.isEmpty ? nil : first
        result.lastName = last.isEmpty ? nil : last
        result.birthDate = birthDate
        result.sex = sex
        result.heightCm = heightCm
        result.experience = experience
        result.goal = goal
        result.weeklyFrequency = weeklyFrequency
        result.equipmentAccess = equipment
        result.limitations = LimitationCodec.encode(limitations, note: limitationNote)
        return result
    }
}
