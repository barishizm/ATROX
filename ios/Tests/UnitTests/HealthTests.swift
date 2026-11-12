import DataKit
import Foundation
import Testing

@testable import ATROX

/// Apple Health integration (P023), against the fake `HealthService`.
@MainActor
struct HealthTests {
    private static let calendar = Calendar(identifier: .gregorian)
    private static let today = Date(timeIntervalSince1970: 1_800_000_000)

    private static func day(_ offset: Int, hour: Int = 8) -> Date {
        let start = calendar.startOfDay(for: today)
        let shifted = calendar.date(byAdding: .day, value: offset, to: start) ?? start
        return calendar.date(byAdding: .hour, value: hour, to: shifted) ?? shifted
    }

    private static func sample(_ offset: Int, _ weight: Double, hour: Int = 8, own: Bool = false) -> HealthWeightSample {
        HealthWeightSample(date: day(offset, hour: hour), weightKg: weight, isFromThisApp: own)
    }

    private static func snapshot(_ offset: Int, _ weight: Double) -> MeasurementSnapshot {
        MeasurementSnapshot(userId: UUID(), input: MeasurementInput(date: day(offset), weightKg: weight))
    }

    // MARK: Import rules

    @Test func importsOnlyNewReadingsOldestFirstAsHealthKit() {
        let fresh = HealthImport.newMeasurements(
            from: [Self.sample(-1, 80), Self.sample(-3, 81)], existing: [], calendar: Self.calendar
        )
        #expect(fresh.map(\.weightKg) == [81, 80])
        #expect(fresh.allSatisfy { $0.source == .healthkit })
    }

    @Test func skipsAReadingThatMatchesAnExistingMeasurementOfThatDay() {
        let fresh = HealthImport.newMeasurements(
            from: [Self.sample(-1, 80.02), Self.sample(-2, 79)],
            existing: [Self.snapshot(-1, 80)], calendar: Self.calendar
        )
        #expect(fresh.map(\.weightKg) == [79])
    }

    @Test func aDifferentWeightOnTheSameDayIsStillImported() {
        let fresh = HealthImport.newMeasurements(
            from: [Self.sample(-1, 82)], existing: [Self.snapshot(-1, 80)], calendar: Self.calendar
        )
        #expect(fresh.map(\.weightKg) == [82])
    }

    @Test func keepsOnlyTheLatestReadingOfEachDay() {
        let fresh = HealthImport.newMeasurements(
            from: [Self.sample(-1, 80, hour: 7), Self.sample(-1, 79, hour: 21), Self.sample(-1, 81, hour: 12)],
            existing: [], calendar: Self.calendar
        )
        #expect(fresh.map(\.weightKg) == [79])
    }

    @Test func neverImportsWhatThisAppWroteOrImplausibleWeights() {
        let fresh = HealthImport.newMeasurements(
            from: [Self.sample(-1, 80, own: true), Self.sample(-2, 5), Self.sample(-3, 900)],
            existing: [], calendar: Self.calendar
        )
        #expect(fresh.isEmpty)
    }

    @Test func startsReadingAtTheNewestLocalDayOrAYearBack() {
        let existing = [Self.snapshot(-10, 80), Self.snapshot(-4, 79)]
        let start = HealthImport.startDate(existing: existing, now: Self.today, calendar: Self.calendar)
        #expect(start == Self.day(-4, hour: 0))
        let yearAgo = HealthImport.startDate(existing: [], now: Self.today, calendar: Self.calendar)
        #expect(yearAgo == Self.calendar.date(byAdding: .year, value: -1, to: Self.today))
    }

    // MARK: Profile screen

    @Test func syncImportsOnceAndIsIdempotent() async throws {
        let health = FakeHealthService(samples: [Self.sample(-1, 80), Self.sample(-2, 81)])
        let env = try await ProfileModelTests.makeHarness(health: health)
        await env.model.load()
        await env.model.syncWithHealth()
        #expect(env.model.healthSync == .imported(2))
        #expect(env.model.measurements.count == 2)
        #expect(env.model.measurements.allSatisfy { $0.input.source == .healthkit })
        await env.model.syncWithHealth()
        #expect(env.model.healthSync == .imported(0))
        #expect(env.model.measurements.count == 2)
        #expect(await health.authorizationRequests == 2)  // the system shows its sheet only the first time
    }

    @Test func newMeasurementIsWrittenToHealthWhenAllowed() async throws {
        let health = FakeHealthService()
        let env = try await ProfileModelTests.makeHarness(health: health)
        await env.model.load()
        #expect(await env.model.addMeasurement(weightKg: 77.5, date: Self.today))
        #expect(await health.saved.map(\.weightKg) == [77.5])
        // What we wrote comes back from Health as ours and must not be imported again.
        await env.model.syncWithHealth()
        #expect(env.model.measurements.count == 1)
    }

    @Test func deniedOrMissingHealthFallsBackToManualEntry() async throws {
        let denied = FakeHealthService(authorizationGranted: false, samples: [Self.sample(-1, 80)])
        let env = try await ProfileModelTests.makeHarness(health: denied)
        await env.model.load()
        #expect(await env.model.addMeasurement(weightKg: 70, date: Self.today))  // local save still works
        #expect(await denied.saved.isEmpty)
        await env.model.syncWithHealth()
        #expect(env.model.healthSync == .imported(0))
        #expect(env.model.measurements.count == 1)

        let absent = try await ProfileModelTests.makeHarness()
        #expect(!absent.model.isHealthAvailable)
        await absent.model.syncWithHealth()
        #expect(absent.model.healthSync == nil)  // nothing happened, nothing to say
    }

    // MARK: Onboarding

    @Test func suggestionWaitsForTheUsersYesAndThenFillsTheDraft() async throws {
        let profile = HealthBodyProfile(
            heightCm: 181.6, weightKg: 82.3, birthDate: OnboardingViewModelTests.date(1993, 4, 5), sex: .male
        )
        let health = FakeHealthService(profile: profile)
        let env = try OnboardingViewModelTests.harness(health: health)
        await env.model.requestHealthSuggestion()
        #expect(await health.authorizationRequests == 1)
        #expect(env.model.healthSuggestion?.heightCm == 182)  // wheel steps: 1 cm
        #expect(env.model.healthSuggestion?.weightKg == 82.5)  // wheel steps: 0.5 kg
        #expect(env.model.draft.heightCm == OnboardingRules.defaultHeightCm)  // not applied yet
        env.model.applyHealthSuggestion()
        #expect(env.model.draft.heightCm == 182)
        #expect(env.model.draft.weightKg == 82.5)
        #expect(env.model.draft.sex == .male)
        #expect(env.model.draft.birthDate == OnboardingViewModelTests.date(1993, 4, 5))
        #expect(env.model.healthSuggestion == nil)
    }

    @Test func decliningTheSuggestionChangesNothing() async throws {
        let health = FakeHealthService(profile: HealthBodyProfile(heightCm: 190, weightKg: 90))
        let env = try OnboardingViewModelTests.harness(health: health)
        await env.model.requestHealthSuggestion()
        env.model.dismissHealthSuggestion()
        env.model.applyHealthSuggestion()  // nothing pending any more
        #expect(env.model.draft.heightCm == OnboardingRules.defaultHeightCm)
        #expect(env.model.draft.weightKg == OnboardingRules.defaultWeightKg)
    }

    @Test func unusableHealthValuesAreDroppedAndEmptyHealthIsReported() async throws {
        let under16 = OnboardingViewModelTests.date(2015, 1, 1)
        let junk = HealthBodyProfile(heightCm: 20, weightKg: 900, birthDate: under16, sex: nil)
        let env = try OnboardingViewModelTests.harness(health: FakeHealthService(profile: junk))
        await env.model.requestHealthSuggestion()
        #expect(env.model.healthSuggestion == nil)
        #expect(env.model.healthFoundNothing)

        let denied = try OnboardingViewModelTests.harness(health: FakeHealthService(authorizationGranted: false))
        await denied.model.requestHealthSuggestion()
        #expect(denied.model.healthSuggestion == nil)
        #expect(denied.model.healthFoundNothing)
        #expect(!(try OnboardingViewModelTests.harness()).model.isHealthAvailable)
    }
}
