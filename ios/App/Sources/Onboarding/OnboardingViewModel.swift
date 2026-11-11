import DataKit
import Foundation
import Observation

/// Drives onboarding part 1 (identity and body data): validation, navigation, draft persistence, final save.
@MainActor
@Observable
final class OnboardingViewModel {
    private(set) var draft: OnboardingDraft
    /// True after an under-16 birth date: the "not yet" screen replaces the question.
    private(set) var isBlocked = false
    private(set) var isSaving = false
    private(set) var saveFailed = false

    let userId: UUID
    private let store: any OnboardingDraftStore
    private let profiles: any ProfileRepository
    private let measurements: any MeasurementRepository
    private let now: () -> Date
    private let calendar: Calendar
    private let localeCode: String

    init(
        userId: UUID,
        store: any OnboardingDraftStore,
        profiles: any ProfileRepository,
        measurements: any MeasurementRepository,
        deviceLocale: Locale = .current,
        localeCode: String = "en",
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userId = userId
        self.store = store
        self.profiles = profiles
        self.measurements = measurements
        self.localeCode = localeCode
        self.now = now
        self.calendar = calendar
        if let saved = store.load(userId: userId) {
            self.draft = saved
        } else {
            var fresh = OnboardingDraft()
            fresh.unitSystem = OnboardingRules.defaultUnitSystem(for: deviceLocale)
            self.draft = fresh
        }
    }

    // MARK: Navigation

    var step: OnboardingStep { draft.step }

    /// Share of the five questions reached (the current one counts); full once part 1 is done.
    var progress: Double {
        guard let index = OnboardingStep.questions.firstIndex(of: draft.step) else { return 1 }
        return Double(index + 1) / Double(OnboardingStep.questions.count)
    }

    var canGoBack: Bool {
        isBlocked || (draft.step != .name && draft.step != .partOneDone)
    }

    var canAdvance: Bool {
        guard !isSaving else { return false }
        switch draft.step {
        case .name: return OnboardingRules.isValidFirstName(draft.firstName) && OnboardingRules.isValidLastName(draft.lastName)
        case .birthDate, .sex, .units: return true
        case .body: return OnboardingRules.isValidHeight(cm: draft.heightCm) && OnboardingRules.isValidWeight(kg: draft.weightKg)
        case .partOneDone: return false
        }
    }

    func back() {
        if isBlocked {
            isBlocked = false
            return
        }
        guard canGoBack, let previous = OnboardingStep(rawValue: draft.step.rawValue - 1) else { return }
        draft.step = previous
        persist()
    }

    /// Moves to the next question. On the last question this saves the profile; await it before reading `step`.
    func advance() async {
        guard canAdvance else { return }
        switch draft.step {
        case .name:
            draft.firstName = OnboardingRules.trimmed(draft.firstName)
            draft.lastName = OnboardingRules.trimmed(draft.lastName)
            go(to: .birthDate)
        case .birthDate:
            confirmBirthDate()
        case .sex:
            go(to: .units)
        case .units:
            go(to: .body)
        case .body:
            await save()
        case .partOneDone:
            break
        }
    }

    // MARK: Name

    var firstName: String {
        get { draft.firstName }
        set { draft.firstName = newValue }
    }

    var lastName: String {
        get { draft.lastName }
        set { draft.lastName = newValue }
    }

    // MARK: Birth date

    /// The date shown by the wheel: the chosen one, or the starting point.
    var birthDateForDisplay: Date { draft.birthDate ?? OnboardingRules.defaultBirthDate(now: now(), calendar: calendar) }

    var birthDateRange: ClosedRange<Date> {
        let today = now()
        let oldest = calendar.date(byAdding: .year, value: -(OnboardingRules.maximumAge + 1), to: today) ?? today
        return oldest...today
    }

    func setBirthDate(_ date: Date) { draft.birthDate = date }

    var birthDateCheck: OnboardingRules.BirthDateCheck {
        OnboardingRules.checkBirthDate(birthDateForDisplay, now: now(), calendar: calendar)
    }

    private func confirmBirthDate() {
        switch birthDateCheck {
        case .valid:
            draft.birthDate = birthDateForDisplay
            go(to: .sex)
        case .tooYoung:
            // Under 16: nothing about this person is kept — not even the name typed so far.
            draft.birthDate = nil
            store.clear(userId: userId)
            isBlocked = true
        case .implausible:
            break  // The wheel is range-limited; kept as a guard.
        }
    }

    // MARK: Other answers

    func setSex(_ sex: Sex) { draft.sex = sex }

    func setUnitSystem(_ system: UnitSystem) { draft.unitSystem = system }

    func setHeight(cm: Double) { draft.heightCm = cm }

    func setWeight(kg: Double) { draft.weightKg = kg }

    // MARK: Saving

    private func save() async {
        guard let birthDate = draft.birthDate else { return go(to: .birthDate) }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        let input = ProfileInput(
            firstName: draft.firstName.isEmpty ? nil : draft.firstName,
            lastName: draft.lastName.isEmpty ? nil : draft.lastName,
            birthDate: birthDate,
            sex: draft.sex,
            heightCm: draft.heightCm,
            unitSystem: draft.unitSystem,
            locale: localeCode
        )
        do {
            // Keep the training fields of a profile that already exists (re-run after a crash, or later parts).
            let existing = try await profiles.profile(userId: userId)
            var merged = input
            if let old = existing?.input {
                merged.experience = old.experience
                merged.goal = old.goal
                merged.weeklyFrequency = old.weeklyFrequency
                merged.equipmentAccess = old.equipmentAccess
                merged.limitations = old.limitations
            }
            try await profiles.upsert(merged, userId: userId)
            try await saveWeight()
            go(to: .partOneDone)
        } catch {
            Log.app.error("Onboarding save failed: \(error)")
            saveFailed = true
        }
    }

    /// One measurement for today: a retry updates it instead of adding a duplicate.
    private func saveWeight() async throws {
        let today = now()
        let input = MeasurementInput(date: today, weightKg: draft.weightKg, source: .manual)
        if let latest = try await measurements.latest(userId: userId),
           latest.input.source == .manual, calendar.isDate(latest.input.date, inSameDayAs: today) {
            try await measurements.update(id: latest.id, with: input)
        } else {
            try await measurements.add(input, userId: userId)
        }
    }

    // MARK: Helpers

    private func go(to step: OnboardingStep) {
        draft.step = step
        persist()
    }

    /// Writes the draft. Never called while an under-16 date is pending.
    private func persist() {
        store.save(draft, userId: userId)
    }
}
