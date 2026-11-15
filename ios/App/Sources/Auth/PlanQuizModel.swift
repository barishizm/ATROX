import DataKit
import Foundation
import Observation

/// State of the pre-sign-up plan questions: name, sex, weight, height, birth date, goals, muscles, level,
/// where to train, days per week, then the "designing your plan" screen. Answers are saved after every step.
@MainActor
@Observable
final class PlanQuizModel {
    enum Step: Int, CaseIterable {
        case name, sex, weight, height, birthDate, goals, muscles, experience, equipment, frequency, limitations
        /// Terms of use and privacy policy.
        case terms
        /// Opt-in to anonymous model contributions (never pre-selected).
        case contribution
        /// The "ATROX is designing your plan" screen; the last one before the sign-up methods.
        case building
    }

    static let maxGoals = 3

    private(set) var answers: PreSignupAnswers
    private(set) var step: Step
    /// An under-16 birth date was entered: the "not yet" screen replaces the question.
    private(set) var isBlocked = false
    /// The birth date shown by the wheel. Kept out of `answers` until it passed the age check.
    private var pendingBirthDate: Date?

    private let store: any PreSignupStore
    private let now: () -> Date
    private let calendar: Calendar

    init(
        store: any PreSignupStore = UserDefaultsPreSignupStore(),
        deviceLocale: Locale = .current,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
        if let saved = store.load() {
            answers = saved
            step = saved.isComplete ? .building : (Step(rawValue: saved.step) ?? .name)
        } else {
            var fresh = PreSignupAnswers()
            fresh.unitSystem = OnboardingRules.defaultUnitSystem(for: deviceLocale)
            answers = fresh
            step = .name
        }
    }

    // MARK: Navigation

    /// Question steps only; the progress bar counts these.
    private static let questionCount = Step.allCases.count - 1

    var progress: Double {
        step == .building ? 1 : Double(step.rawValue + 1) / Double(Self.questionCount)
    }

    var canGoBack: Bool { isBlocked || step != .name }

    var canAdvance: Bool {
        switch step {
        case .name: OnboardingRules.isValidFirstName(answers.firstName)
        case .sex: answers.sex != nil
        case .weight: OnboardingRules.isValidWeight(kg: answers.weightKg)
        case .height: OnboardingRules.isValidHeight(cm: answers.heightCm)
        case .birthDate, .muscles, .frequency, .terms: true
        case .goals: !answers.goals.isEmpty
        case .contribution: answers.contribution != nil
        case .limitations: answers.noLimitations || !answers.limitations.isEmpty
        case .experience: answers.experience != nil
        case .equipment: answers.equipment != nil
        case .building: false
        }
    }

    func back() {
        if isBlocked {
            isBlocked = false
            return
        }
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        // Going back to change an answer reopens the questions; the plan screen follows again after the last one.
        if step == .building { answers.isComplete = false }
        step = previous
        persist()
    }

    func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        switch step {
        case .name:
            answers.firstName = OnboardingRules.trimmed(answers.firstName)
        case .birthDate:
            switch OnboardingRules.checkBirthDate(birthDateForDisplay, now: now(), calendar: calendar) {
            case .valid:
                answers.birthDate = birthDateForDisplay
            case .tooYoung:
                // Under 16: nothing about this person is kept.
                answers.birthDate = nil
                pendingBirthDate = nil
                store.clear()
                isBlocked = true
                return
            case .implausible:
                return
            }
        case .terms:
            answers.acceptedLegal = true
        default:
            break
        }
        step = next
        if next == .building { answers.isComplete = true }
        persist()
    }

    private func persist() {
        answers.step = step.rawValue
        store.save(answers)
    }

    // MARK: Answers

    var firstName: String {
        get { answers.firstName }
        set { answers.firstName = newValue }
    }

    func setSex(_ sex: Sex) { answers.sex = sex }

    func setUnitSystem(_ system: UnitSystem) { answers.unitSystem = system }

    func setWeight(kg: Double) { answers.weightKg = kg }

    func setHeight(cm: Double) { answers.heightCm = cm }

    var birthDateForDisplay: Date {
        pendingBirthDate ?? answers.birthDate ?? OnboardingRules.defaultBirthDate(now: now(), calendar: calendar)
    }

    var birthDateRange: ClosedRange<Date> {
        let today = now()
        let oldest = calendar.date(byAdding: .year, value: -(OnboardingRules.maximumAge + 1), to: today) ?? today
        return oldest...today
    }

    func setBirthDate(_ date: Date) { pendingBirthDate = date }

    /// Picks or drops a goal; at most `maxGoals` can be selected.
    func toggleGoal(_ goal: Goal) {
        if let index = answers.goals.firstIndex(of: goal) {
            answers.goals.remove(at: index)
        } else if answers.goals.count < Self.maxGoals {
            answers.goals.append(goal)
        }
    }

    var canPickMoreGoals: Bool { answers.goals.count < Self.maxGoals }

    func toggleMuscle(_ muscle: FocusMuscle) {
        if let index = answers.focusMuscles.firstIndex(of: muscle) {
            answers.focusMuscles.remove(at: index)
        } else {
            answers.focusMuscles.append(muscle)
        }
    }

    /// Picks or drops a body area to protect; picking one clears "no limitations".
    func toggleLimitation(_ area: BodyLimitation) {
        answers.noLimitations = false
        if let index = answers.limitations.firstIndex(of: area) {
            answers.limitations.remove(at: index)
        } else {
            answers.limitations.append(area)
        }
    }

    /// "No limitations" is exclusive: it clears the areas.
    func toggleNoLimitations() {
        answers.noLimitations.toggle()
        if answers.noLimitations { answers.limitations = [] }
    }

    func setContribution(_ granted: Bool) { answers.contribution = granted }

    func setExperience(_ value: Experience) { answers.experience = value }

    func setEquipment(_ value: EquipmentAccess) { answers.equipment = value }

    func setWeeklyFrequency(_ days: Int) {
        answers.weeklyFrequency = Swift.min(
            Swift.max(days, OnboardingRules.weeklyFrequencyRange.lowerBound),
            OnboardingRules.weeklyFrequencyRange.upperBound
        )
    }
}
