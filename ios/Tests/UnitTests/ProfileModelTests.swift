import DataKit
import Foundation
import SwiftData
import Testing

@testable import GymAnalyzer

@MainActor
struct ProfileModelTests {
    struct Harness {
        let model: ProfileModel
        let appearance: AppearanceSettings
        let consents: ConsentService
        let measurements: SwiftDataMeasurementRepository
        let userId: UUID
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func makeHarness(profile: Bool = true, health: any HealthService = UnavailableHealthService()) async throws -> Harness {
        let container = try DataStore.inMemory()
        let defaults = UserDefaults(suiteName: "ProfileModelTests-\(UUID())")!
        let appearance = AppearanceSettings(defaults: defaults)
        let consentService = ConsentService(repository: SwiftDataConsentRepository(modelContainer: container))
        let measurements = SwiftDataMeasurementRepository(modelContainer: container)
        let userId = UUID()
        let profiles = SwiftDataProfileRepository(modelContainer: container)
        if profile {
            try await profiles.upsert(
                ProfileInput(firstName: "Ada", lastName: "Lovelace", birthDate: Calendar(identifier: .gregorian).date(byAdding: .year, value: -30, to: now)!, heightCm: 178),
                userId: userId
            )
        }
        let model = ProfileModel(
            userId: userId, email: "ada@example.com", profiles: profiles, measurements: measurements,
            settings: SwiftDataSettingsRepository(modelContainer: container), consents: consentService,
            appearance: appearance, health: health, now: { now }, calendar: Calendar(identifier: .gregorian)
        )
        return Harness(model: model, appearance: appearance, consents: consentService, measurements: measurements, userId: userId)
    }

    @Test func loadReadsProfileMeasurementsAndSettings() async throws {
        let env = try await Self.makeHarness()
        try await env.measurements.add(MeasurementInput(date: Self.now, weightKg: 70), userId: env.model.userId)
        await env.model.load()
        #expect(env.model.loadState == .loaded)
        #expect(env.model.displayName == "Ada Lovelace")
        #expect(env.model.age == 30)
        #expect(env.model.latestWeightKg == 70)
        #expect(env.model.settings == SettingsInput(theme: .dark))  // device default theme is dark
    }

    @Test func loadWithoutProfileStillLoads() async throws {
        let env = try await Self.makeHarness(profile: false)
        await env.model.load()
        #expect(env.model.loadState == .loaded)
        #expect(env.model.profile == nil)
        #expect(env.model.displayName == nil)
    }

    @Test func savingProfileKeepsEditsAndPending() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        var input = try #require(env.model.profile?.input)
        input.firstName = "Augusta"
        input.goal = .strength
        #expect(await env.model.saveProfile(input))
        #expect(env.model.displayName == "Augusta Lovelace")
        #expect(env.model.profile?.input.goal == .strength)
        #expect(env.model.profile?.syncState == .pending)
    }

    @Test func invalidProfileIsNotSavedAndFlagsFailure() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        var input = try #require(env.model.profile?.input)
        input.heightCm = 20
        #expect(!(await env.model.saveProfile(input)))
        #expect(env.model.actionFailed)
        #expect(env.model.profile?.input.heightCm == 178)
    }

    @Test func measurementsAreAddedDeletedAndRangeChecked() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        #expect(await env.model.addMeasurement(weightKg: 71, date: Self.now.addingTimeInterval(-86_400)))
        #expect(await env.model.addMeasurement(weightKg: 69.5, date: Self.now))
        #expect(!(await env.model.addMeasurement(weightKg: 5, date: Self.now)))
        #expect(env.model.measurements.map(\.input.weightKg) == [69.5, 71])
        #expect(env.model.latestWeightKg == 69.5)
        #expect(env.model.weightChangeKg == -1.5)
        let newest = try #require(env.model.measurements.first)
        await env.model.deleteMeasurement(id: newest.id)
        #expect(env.model.measurements.map(\.input.weightKg) == [71])
    }

    @Test func unitSwitchUpdatesProfileAndSettingsTogether() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        #expect(env.model.weightUnit == .kilograms)
        await env.model.setUnitSystem(.imperial)
        #expect(env.model.weightUnit == .pounds)
        #expect(env.model.lengthUnit == .feetInches)
        #expect(env.model.profile?.input.unitSystem == .imperial)
        #expect(env.model.settings.weightUnit == .lb)
        #expect(env.model.settings.lengthUnit == .inch)
        await env.model.setUnitSystem(.metric)
        #expect(env.model.settings.weightUnit == .kg)
        #expect(env.model.settings.lengthUnit == .cm)
    }

    @Test func themeIsAppliedAndStored() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        #expect(env.appearance.theme == .dark)  // product default before anything is stored
        #expect(env.model.settings.theme == .dark)  // the stored row follows the device choice
        await env.model.setTheme(.light)
        #expect(env.appearance.theme == .light)
        #expect(env.appearance.preference == .light)
        #expect(env.model.settings.theme == .light)
    }

    @Test func contributionToggleKeepsTheAuditTrail() async throws {
        let env = try await Self.makeHarness()
        await env.model.load()
        #expect(!env.model.isContributing)
        await env.model.setContribution(true)
        #expect(env.model.isContributing)
        await env.model.setContribution(false)
        #expect(!env.model.isContributing)
        #expect(env.model.contribution == .declined)
        #expect(env.model.consentHistory.map(\.granted) == [false, true])  // newest first
    }
}

struct MeasurementTrendTests {
    private func snapshot(_ day: Int, _ kg: Double) -> MeasurementSnapshot {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
        return MeasurementSnapshot(userId: UUID(), input: MeasurementInput(date: date, weightKg: kg))
    }

    @Test func pointsRunOldestFirst() {
        let points = MeasurementTrend.points(from: [snapshot(2, 70), snapshot(0, 72), snapshot(1, 71)])
        #expect(points.map(\.kilograms) == [72, 71, 70])
    }

    @Test func changeNeedsTwoPoints() {
        #expect(MeasurementTrend.change(of: []) == nil)
        #expect(MeasurementTrend.change(of: MeasurementTrend.points(from: [snapshot(0, 70)])) == nil)
        #expect(MeasurementTrend.change(of: MeasurementTrend.points(from: [snapshot(0, 72), snapshot(5, 70.5)])) == -1.5)
    }
}
