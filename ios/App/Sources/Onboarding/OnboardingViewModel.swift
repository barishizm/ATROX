import DataKit
import Foundation
import Observation
import StrengthKit

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
    private let consents: ConsentService
    private let engine: any ScoreEngine
    private let setStore: any OnboardingSetStore
    private let now: () -> Date
    private let calendar: Calendar
    private let localeCode: String

    init(
        userId: UUID,
        store: any OnboardingDraftStore,
        profiles: any ProfileRepository,
        measurements: any MeasurementRepository,
        consents: ConsentService,
        engine: any ScoreEngine = PlaceholderScoreEngine(),
        setStore: any OnboardingSetStore = UserDefaultsOnboardingSetStore(),
        deviceLocale: Locale = .current,
        localeCode: String = "en",
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userId = userId
        self.store = store
        self.profiles = profiles
        self.measurements = measurements
        self.consents = consents
        self.engine = engine
        self.setStore = setStore
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
        isBlocked || (draft.step != .name && draft.step != .lifts)
    }

    var canAdvance: Bool {
        guard !isSaving else { return false }
        switch draft.step {
        case .name: return OnboardingRules.isValidFirstName(draft.firstName) && OnboardingRules.isValidLastName(draft.lastName)
        case .birthDate, .sex, .units: return true
        case .body: return OnboardingRules.isValidHeight(cm: draft.heightCm) && OnboardingRules.isValidWeight(kg: draft.weightKg)
        case .experience: return draft.experience != nil
        case .goal: return draft.goal != nil
        case .frequency: return OnboardingRules.weeklyFrequencyRange.contains(draft.weeklyFrequency)
        case .equipment: return draft.equipment != nil
        case .limitations: return draft.noLimitations || !draft.limitations.isEmpty
        // The consent screens have their own buttons (see `acceptLegal`, `decideContribution`).
        case .lifts: return true  // Every card may be skipped.
        case .terms, .contribution, .result: return false
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
        case .body:
            await save()
        case .sex, .units, .experience, .goal, .frequency, .equipment:
            // Plain questions: the next step is the next case (the enum order is persisted, so it is stable).
            if let next = OnboardingStep(rawValue: draft.step.rawValue + 1) { go(to: next) }
        case .limitations: await save()
        case .lifts: saveLifts()
        case .terms, .contribution, .result: break
        }
    }

    // MARK: Consents (P020)

    /// "Kabul ediyorum ve devam et": stores terms + privacy with their versions, then asks about contribution.
    func acceptLegal() async {
        guard draft.step == .terms, !isSaving else { return }
        await run { [consents, userId] in try await consents.acceptLegal(userId: userId) }
        if !saveFailed { go(to: .contribution) }
    }

    /// Answers "Modeli birlikte geliştirelim". Both answers are stored; only the explicit button grants.
    func decideContribution(_ granted: Bool) async {
        guard draft.step == .contribution, !isSaving else { return }
        await run { [consents, userId] in try await consents.setContribution(granted, userId: userId) }
        if !saveFailed { go(to: .lifts) }
    }

    private func run(_ work: () async throws -> Void) async {
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            try await work()
        } catch {
            Log.app.error("Onboarding consent save failed: \(error)")
            saveFailed = true
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

    // MARK: Training profile (part 2)

    func setExperience(_ value: Experience) { draft.experience = value }

    func setGoal(_ value: Goal) { draft.goal = value }

    func setWeeklyFrequency(_ days: Int) {
        draft.weeklyFrequency = Swift.min(Swift.max(days, OnboardingRules.weeklyFrequencyRange.lowerBound),
                                          OnboardingRules.weeklyFrequencyRange.upperBound)
    }

    func setEquipment(_ value: EquipmentAccess) { draft.equipment = value }

    /// Toggles one body area; picking an area clears "no limitations".
    func toggleLimitation(_ area: BodyLimitation) {
        draft.noLimitations = false
        if let index = draft.limitations.firstIndex(of: area) {
            draft.limitations.remove(at: index)
        } else {
            draft.limitations.append(area)
        }
    }

    /// "No limitations" is exclusive: it clears the areas and the note.
    func toggleNoLimitations() {
        draft.noLimitations.toggle()
        if draft.noLimitations {
            draft.limitations = []
            draft.limitationNote = ""
        }
    }

    var limitationNote: String {
        get { draft.limitationNote }
        set {
            draft.limitationNote = String(newValue.prefix(OnboardingRules.limitationNoteLimit))
            if !draft.limitationNote.isEmpty { draft.noLimitations = false }
        }
    }

    // MARK: First strength profile (part 3)

    var weightUnit: WeightUnit { draft.unitSystem == .metric ? .kilograms : .pounds }

    var liftImplement: LiftImplement { OnboardingLifts.implement(for: draft.equipment) }

    var liftEntries: [LiftEntry] { draft.lifts ?? OnboardingLifts.blank() }

    func entry(for lift: BasicLift) -> LiftEntry {
        liftEntries.first { $0.lift == lift } ?? LiftEntry(lift: lift)
    }

    /// `value` is in the user's unit; `nil` or a non-positive number clears the weight.
    func setLiftWeight(_ lift: BasicLift, value: Double?) {
        update(lift) { entry in
            guard let value, value.isFinite, value > 0 else { return entry.weightKg = nil }
            entry.weightKg = Swift.min(weightUnit.kilograms(from: value), OnboardingLifts.maximumWeightKg)
        }
    }

    func setLiftReps(_ lift: BasicLift, reps: Int) {
        update(lift) { $0.reps = Swift.min(Swift.max(reps, OnboardingLifts.repsRange.lowerBound), OnboardingLifts.repsRange.upperBound) }
    }

    func setLiftSkipped(_ lift: BasicLift, _ skipped: Bool) {
        update(lift) { $0.skipped = skipped }
    }

    private func update(_ lift: BasicLift, _ change: (inout LiftEntry) -> Void) {
        var entries = liftEntries
        guard let index = entries.firstIndex(where: { $0.lift == lift }) else { return }
        change(&entries[index])
        draft.lifts = entries
        persist()
    }

    /// Sets the score can be computed from, in card order.
    var reportedSets: [LiftSet] {
        let implement = liftImplement
        return liftEntries.compactMap { entry in
            guard entry.isComplete, let weight = entry.weightKg, let reps = entry.reps else { return nil }
            return LiftSet(lift: entry.lift, implement: implement, weightKg: weight, reps: reps)
        }
    }

    /// One score per reported lift; empty when every card was skipped.
    var results: [LiftResult] {
        let athlete = AthleteProfile(
            sex: scoreSex, bodyweightKg: draft.weightKg,
            ageYears: draft.birthDate.map { OnboardingRules.age(birthDate: $0, now: now(), calendar: calendar) } ?? 30
        )
        return reportedSets.compactMap { set in
            engine.estimate(set, for: athlete).map { LiftResult(lift: $0.lift, score: $0.score) }
        }
    }

    private var scoreSex: ScoreSex {
        switch draft.sex {
        case .male: .male
        case .female: .female
        case .unspecified: .unspecified
        }
    }

    private func saveLifts() {
        // Becomes one Workout (source = onboarding) in P032; see `OnboardingSetStore`.
        setStore.save(reportedSets, userId: userId)
        go(to: .result)
    }

    /// Onboarding is over: the resume draft is no longer needed.
    func finish() { store.clear(userId: userId) }

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
            // Part 1 (saved after the body step) must not wipe training answers already on file, and the
            // final save writes the whole profile at once.
            var merged = input
            if let old = try await profiles.profile(userId: userId)?.input {
                merged.experience = old.experience
                merged.goal = old.goal
                merged.weeklyFrequency = old.weeklyFrequency
                merged.equipmentAccess = old.equipmentAccess
                merged.limitations = old.limitations
            }
            if draft.step == .limitations {
                merged.experience = draft.experience ?? merged.experience
                merged.goal = draft.goal ?? merged.goal
                merged.weeklyFrequency = draft.weeklyFrequency
                merged.equipmentAccess = draft.equipment ?? merged.equipmentAccess
                merged.limitations = LimitationCodec.encode(draft.limitations, note: draft.limitationNote)
            }
            try await profiles.upsert(merged, userId: userId)
            if draft.step == .body {
                try await saveWeight()
                go(to: .experience)
            } else {
                go(to: .terms)
            }
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
