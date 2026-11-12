import DataKit
import Foundation
import Observation

/// State behind the Profile tab: profile, weight history, settings and the consent choice that settings shows.
@MainActor
@Observable
final class ProfileModel {
    enum LoadState: Equatable { case loading, loaded, failed }

    private(set) var loadState: LoadState = .loading
    private(set) var profile: ProfileSnapshot?
    /// Newest day first.
    private(set) var measurements: [MeasurementSnapshot] = []
    private(set) var settings = SettingsInput()
    private(set) var contribution: ConsentStatus = .notAsked
    /// Newest first.
    private(set) var consentHistory: [ConsentSnapshot] = []
    /// A save or delete went wrong; the screen that triggered it shows a message.
    private(set) var actionFailed = false
    /// Outcome of the last "sync with Apple Health" press; nil until the user presses it.
    private(set) var healthSync: HealthSyncOutcome?
    private(set) var isSyncingHealth = false

    let userId: UUID
    let email: String?
    private let profiles: any ProfileRepository
    private let measurementRepository: any MeasurementRepository
    private let settingsRepository: any SettingsRepository
    private let consents: ConsentService
    private let appearance: AppearanceSettings
    private let health: any HealthService
    private let now: () -> Date
    private let calendar: Calendar

    init(
        userId: UUID, email: String?, profiles: any ProfileRepository, measurements: any MeasurementRepository,
        settings: any SettingsRepository, consents: ConsentService, appearance: AppearanceSettings,
        health: any HealthService = UnavailableHealthService(),
        now: @escaping () -> Date = { Date() }, calendar: Calendar = .current
    ) {
        self.userId = userId
        self.email = email
        self.profiles = profiles
        self.measurementRepository = measurements
        self.settingsRepository = settings
        self.consents = consents
        self.appearance = appearance
        self.health = health
        self.now = now
        self.calendar = calendar
    }

    // MARK: Loading

    func load() async {
        do {
            profile = try await profiles.profile(userId: userId)
            measurements = try await measurementRepository.all(userId: userId)
            settings = try await settingsRepository.settings(userId: userId).input
            try await refreshConsent()
            // This device's choice is authoritative until sync exists (Faz 11); keep the stored row in step with it.
            if settings.theme != appearance.theme {
                let theme = appearance.theme
                settings = try await settingsRepository.update(SettingsInput.with(settings) { $0.theme = theme }, userId: userId).input
            }
            loadState = .loaded
        } catch {
            Log.app.error("Profile load failed: \(error)")
            loadState = .failed
        }
    }

    private func refreshConsent() async throws {
        contribution = try await consents.status(of: .mlContribution, userId: userId)
        consentHistory = try await consents.history(userId: userId)
    }

    // MARK: Derived values

    var unitSystem: UnitSystem { profile?.input.unitSystem ?? .metric }
    var weightUnit: WeightUnit { unitSystem == .imperial ? .pounds : .kilograms }
    var lengthUnit: LengthUnit { unitSystem == .imperial ? .feetInches : .centimeters }

    var displayName: String? {
        let parts = [profile?.input.firstName, profile?.input.lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var age: Int? {
        profile.map { OnboardingRules.age(birthDate: $0.input.birthDate, now: now(), calendar: calendar) }
    }

    var latestWeightKg: Double? { measurements.first?.input.weightKg }
    var trendPoints: [WeightPoint] { MeasurementTrend.points(from: measurements) }
    var weightChangeKg: Double? { MeasurementTrend.change(of: trendPoints) }
    var isHealthAvailable: Bool { health.isAvailable }
    var isContributing: Bool { contribution.isGranted }

    // MARK: Profile

    @discardableResult
    func saveProfile(_ input: ProfileInput) async -> Bool {
        await perform { [self] in profile = try await profiles.upsert(input, userId: userId) }
    }

    /// One switch for everything: profile unit system plus the weight and length units in settings.
    func setUnitSystem(_ system: UnitSystem) async {
        guard var input = profile?.input, input.unitSystem != system else { return }
        input.unitSystem = system
        let didSave = await perform { [self] in profile = try await profiles.upsert(input, userId: userId) }
        guard didSave else { return }
        await updateSettings { settings in
            settings.weightUnit = system == .imperial ? .lb : .kg
            settings.lengthUnit = system == .imperial ? .inch : .cm
        }
    }

    // MARK: Measurements

    @discardableResult
    func addMeasurement(weightKg: Double, date: Date) async -> Bool {
        guard OnboardingRules.isValidWeight(kg: weightKg) else { return false }
        let didSave = await perform { [self] in
            try await measurementRepository.add(MeasurementInput(date: date, weightKg: weightKg), userId: userId)
            measurements = try await measurementRepository.all(userId: userId)
        }
        // Mirror into Health when the user allowed it; a failure there never blocks the local save.
        if didSave, await health.canWriteWeight() { await health.saveWeight(kilograms: weightKg, date: date) }
        return didSave
    }

    /// "Sync with Apple Health": asks for permission if needed, then imports readings newer than the local ones.
    /// Denied or unavailable Health simply imports nothing.
    func syncWithHealth() async {
        guard health.isAvailable, !isSyncingHealth else { return }
        isSyncingHealth = true
        healthSync = nil
        defer { isSyncingHealth = false }
        _ = await health.requestAuthorization()
        let start = HealthImport.startDate(existing: measurements, now: now(), calendar: calendar)
        let samples = await health.weightSamples(since: start)
        let fresh = HealthImport.newMeasurements(from: samples, existing: measurements, calendar: calendar)
        guard !fresh.isEmpty else {
            healthSync = .imported(0)
            return
        }
        let didSave = await perform { [self] in
            for input in fresh { try await measurementRepository.add(input, userId: userId) }
            measurements = try await measurementRepository.all(userId: userId)
        }
        healthSync = didSave ? .imported(fresh.count) : .failed
    }

    func deleteMeasurement(id: UUID) async {
        await perform { [self] in
            try await measurementRepository.delete(id: id)
            measurements = try await measurementRepository.all(userId: userId)
        }
    }

    // MARK: Settings

    func setTheme(_ theme: ThemePreference) async {
        appearance.theme = theme  // Apply at once; the repository write follows.
        await updateSettings { $0.theme = theme }
    }

    private func updateSettings(_ change: (inout SettingsInput) -> Void) async {
        var updated = settings
        change(&updated)
        await perform { [self] in settings = try await settingsRepository.update(updated, userId: userId).input }
    }

    // MARK: Privacy

    /// The privacy switch. Turning it on is an explicit opt-in; turning it off appends a withdrawal row.
    func setContribution(_ granted: Bool) async {
        await perform { [self] in
            if granted {
                try await consents.setContribution(true, userId: userId)
            } else {
                try await consents.withdrawContribution(userId: userId)
            }
            try await refreshConsent()
        }
    }

    @discardableResult
    private func perform(_ work: () async throws -> Void) async -> Bool {
        actionFailed = false
        do {
            try await work()
            return true
        } catch {
            Log.app.error("Profile action failed: \(error)")
            actionFailed = true
            return false
        }
    }
}

enum HealthSyncOutcome: Equatable {
    case imported(Int)
    case failed
}

private extension SettingsInput {
    static func with(_ base: SettingsInput, _ change: (inout SettingsInput) -> Void) -> SettingsInput {
        var copy = base
        change(&copy)
        return copy
    }
}
