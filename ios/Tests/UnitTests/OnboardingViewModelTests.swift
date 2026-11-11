import DataKit
import Foundation
import Testing

@testable import GymAnalyzer

@MainActor
struct OnboardingViewModelTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-06-15 12:00 UTC.
    static let today = Date(timeIntervalSince1970: 1_781_524_800)

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    struct Harness {
        let model: OnboardingViewModel
        let store: UserDefaultsOnboardingDraftStore
        let profiles: SwiftDataProfileRepository
        let measurements: SwiftDataMeasurementRepository
        let consentRepository: SwiftDataConsentRepository
        let userId: UUID
    }

    static func harness(
        userId: UUID = UUID(), defaults: UserDefaults? = nil, locale: Locale = Locale(identifier: "tr_TR")
    ) throws -> Harness {
        let defaults = defaults ?? UserDefaults(suiteName: "onboarding-tests-\(UUID().uuidString)")!
        let container = try DataStore.inMemory()
        let store = UserDefaultsOnboardingDraftStore(defaults: defaults)
        let profiles = SwiftDataProfileRepository(modelContainer: container)
        let measurements = SwiftDataMeasurementRepository(modelContainer: container)
        let consentRepository = SwiftDataConsentRepository(modelContainer: container)
        let model = OnboardingViewModel(
            userId: userId, store: store, profiles: profiles, measurements: measurements,
            consents: ConsentService(repository: consentRepository),
            deviceLocale: locale, localeCode: "tr", now: { today }, calendar: calendar
        )
        return Harness(
            model: model, store: store, profiles: profiles, measurements: measurements,
            consentRepository: consentRepository, userId: userId
        )
    }

    // MARK: Rules

    @Test func ageBoundaryIsSixteenYears() {
        let cal = Self.calendar
        let now = Self.today
        #expect(OnboardingRules.checkBirthDate(Self.date(2010, 6, 15), now: now, calendar: cal) == .valid)
        #expect(OnboardingRules.checkBirthDate(Self.date(2010, 6, 16), now: now, calendar: cal) == .tooYoung)
        #expect(OnboardingRules.checkBirthDate(Self.date(2011, 6, 15), now: now, calendar: cal) == .tooYoung)  // 15
        #expect(OnboardingRules.checkBirthDate(Self.date(2027, 1, 1), now: now, calendar: cal) == .implausible)
        #expect(OnboardingRules.checkBirthDate(Self.date(1900, 1, 1), now: now, calendar: cal) == .implausible)
    }

    @Test func namesAreTrimmedAndLimited() {
        #expect(!OnboardingRules.isValidFirstName("   "))
        #expect(OnboardingRules.isValidFirstName("  Ada "))
        #expect(!OnboardingRules.isValidFirstName(String(repeating: "a", count: 51)))
        #expect(OnboardingRules.isValidLastName(""))
    }

    @Test func unitDefaultFollowsRegion() {
        #expect(OnboardingRules.defaultUnitSystem(for: Locale(identifier: "en_US")) == .imperial)
        #expect(OnboardingRules.defaultUnitSystem(for: Locale(identifier: "tr_TR")) == .metric)
        #expect(OnboardingRules.defaultUnitSystem(for: Locale(identifier: "en_GB")) == .metric)
    }

    // MARK: Navigation

    @Test func startsOnNameAndNeedsAFirstName() throws {
        let env = try Self.harness()
        #expect(env.model.step == .name)
        #expect(!env.model.canGoBack)
        #expect(!env.model.canAdvance)
        env.model.firstName = "Ada"
        #expect(env.model.canAdvance)
    }

    @Test func walksThroughAllStepsAndBack() async throws {
        let env = try Self.harness()
        env.model.firstName = " Ada "
        await env.model.advance()
        #expect(env.model.step == .birthDate)
        #expect(env.model.draft.firstName == "Ada")
        env.model.setBirthDate(Self.date(1995, 3, 2))
        await env.model.advance()
        #expect(env.model.step == .sex)
        await env.model.advance()
        #expect(env.model.step == .units)
        await env.model.advance()
        #expect(env.model.step == .body)
        env.model.back()
        #expect(env.model.step == .units)
        #expect(env.model.canGoBack)
    }

    @Test func progressGrowsAcrossQuestions() async throws {
        let env = try Self.harness()
        let first = env.model.progress
        env.model.firstName = "Ada"
        await env.model.advance()
        #expect(env.model.progress > first)
        #expect(first > 0 && env.model.progress < 1)
    }

    // MARK: Under 16

    @Test func underSixteenIsBlockedAndNothingIsKept() async throws {
        let env = try Self.harness()
        env.model.firstName = "Kid"
        await env.model.advance()
        env.model.setBirthDate(Self.date(2012, 1, 1))  // 14
        await env.model.advance()
        #expect(env.model.isBlocked)
        #expect(env.model.step == .birthDate)
        #expect(env.model.draft.birthDate == nil)
        #expect(env.store.load(userId: env.userId) == nil)
        #expect(try await env.profiles.profile(userId: env.userId) == nil)
        #expect(try await env.measurements.latest(userId: env.userId) == nil)
    }

    @Test func blockedScreenGoesBackToTheDateAndAllowsACorrection() async throws {
        let env = try Self.harness()
        env.model.firstName = "Ada"
        await env.model.advance()
        env.model.setBirthDate(Self.date(2012, 1, 1))
        await env.model.advance()
        env.model.back()
        #expect(!env.model.isBlocked)
        #expect(env.model.step == .birthDate)
        env.model.setBirthDate(Self.date(2002, 1, 1))
        await env.model.advance()
        #expect(env.model.step == .sex)
        #expect(env.model.draft.birthDate == Self.date(2002, 1, 1))
    }

    // MARK: Body, units

    @Test func heightAndWeightBoundsAreEnforced() async throws {
        let env = try Self.harness()
        env.model.firstName = "Ada"
        for _ in 0..<4 { await env.model.advance() }
        #expect(env.model.step == .body)
        env.model.setHeight(cm: 99)
        #expect(!env.model.canAdvance)
        env.model.setHeight(cm: 180)
        env.model.setWeight(kg: 301)
        #expect(!env.model.canAdvance)
        env.model.setWeight(kg: 82.5)
        #expect(env.model.canAdvance)
    }

    @Test func unitSystemDefaultsFromDeviceRegion() throws {
        #expect(try Self.harness(locale: Locale(identifier: "en_US")).model.draft.unitSystem == .imperial)
        #expect(try Self.harness(locale: Locale(identifier: "tr_TR")).model.draft.unitSystem == .metric)
    }

    // MARK: Saving

    @Test func finishingSavesProfileAndWeightInMetricStorage() async throws {
        let env = try Self.harness()
        env.model.firstName = "Ada"
        env.model.lastName = "Lovelace"
        await env.model.advance()
        env.model.setBirthDate(Self.date(1995, 3, 2))
        await env.model.advance()
        env.model.setSex(.female)
        await env.model.advance()
        env.model.setUnitSystem(.imperial)
        await env.model.advance()
        // 5′10″ and 150 lb, entered in imperial, are stored as cm / kg.
        env.model.setHeight(cm: LengthFormat.centimeters(feet: 5, inches: 10))
        env.model.setWeight(kg: WeightUnit.pounds.kilograms(from: 150))
        await env.model.advance()

        #expect(env.model.step == .experience)
        let profile = try #require(try await env.profiles.profile(userId: env.userId)).input
        #expect(profile.firstName == "Ada")
        #expect(profile.lastName == "Lovelace")
        #expect(profile.sex == .female)
        #expect(profile.unitSystem == .imperial)
        #expect(profile.locale == "tr")
        #expect(abs(profile.heightCm - 177.8) < 0.01)
        #expect(profile.birthDate == Self.date(1995, 3, 2))
        let weight = try #require(try await env.measurements.latest(userId: env.userId)).input
        #expect(abs(weight.weightKg - 68.04) < 0.01)
        #expect(weight.source == .manual)
    }

    @Test func emptyLastNameAndRetrySaveOneMeasurementOnly() async throws {
        let env = try Self.harness()
        env.model.firstName = "Ada"
        await env.model.advance()
        env.model.setBirthDate(Self.date(1995, 3, 2))
        for _ in 0..<3 { await env.model.advance() }
        await env.model.advance()  // save
        #expect(env.model.step == .experience)
        #expect(try await env.profiles.profile(userId: env.userId)?.input.lastName == nil)

        // Saving the same day again (retry after a failure): the measurement is updated, not duplicated.
        env.model.back()
        await env.model.advance()
        #expect(env.model.step == .experience)
        #expect(try await env.measurements.all(userId: env.userId).count == 1)
    }

    // MARK: Resume

    @Test func resumesFromTheSavedDraft() async throws {
        let userId = UUID()
        let defaults = UserDefaults(suiteName: "onboarding-resume-\(UUID().uuidString)")!
        let first = try Self.harness(userId: userId, defaults: defaults)
        first.model.firstName = "Ada"
        await first.model.advance()
        first.model.setBirthDate(Self.date(1995, 3, 2))
        await first.model.advance()
        first.model.setSex(.male)
        await first.model.advance()
        #expect(first.model.step == .units)

        // "App killed": a new model over the same stored draft.
        let second = try Self.harness(userId: userId, defaults: defaults)
        #expect(second.model.step == .units)
        #expect(second.model.draft.firstName == "Ada")
        #expect(second.model.draft.birthDate == Self.date(1995, 3, 2))
        #expect(second.model.draft.sex == .male)
        #expect(second.model.canGoBack)
    }

    @Test func draftsOfDifferentUsersDoNotMix() async throws {
        let defaults = UserDefaults(suiteName: "onboarding-users-\(UUID().uuidString)")!
        let adaEnv = try Self.harness(defaults: defaults)
        adaEnv.model.firstName = "Ada"
        await adaEnv.model.advance()
        let otherEnv = try Self.harness(defaults: defaults)
        #expect(otherEnv.model.step == .name)
        #expect(otherEnv.model.draft.firstName.isEmpty)
    }
}
