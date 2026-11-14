@testable import DataKit
import Foundation
import StrengthKit
import Testing

private let bench = "barbell-bench-press-medium-grip"

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private let inputs = ContributionInputs(
    sex: .female, birthDate: date("1996-03-10T00:00:00Z"), heightCm: 167.4, bodyweightKg: 63.6, experience: .twoToFiveYears, weeklyFrequency: 4
)

private func sets(day: Int, weight: Double, reps: Int, warmup: Bool = false) -> ScoredSet {
    ScoredSet(set: ScoringSet(day: day, weightKg: weight, reps: reps, rir: 2, isWarmup: warmup))
}

@Suite struct ContributionBandingTests {
    @Test func bandsFloorAndClamp() {
        #expect(ContributionBanding.ageBand(29) == 25)
        #expect(ContributionBanding.ageBand(30) == 30)
        #expect(ContributionBanding.ageBand(120) == 95)
        #expect(ContributionBanding.heightBand(167.4) == 165)
        #expect(ContributionBanding.heightBand(100) == 120)
        #expect(ContributionBanding.bodyweight(63.5) == 64)
        #expect(ContributionBanding.bodyweight(400) == 300)
        #expect(ContributionBanding.frequencyBand(0) == "1-2")
        #expect(ContributionBanding.frequencyBand(2) == "1-2")
        #expect(ContributionBanding.frequencyBand(3) == "3-4")
        #expect(ContributionBanding.frequencyBand(5) == "5-6")
        #expect(ContributionBanding.frequencyBand(7) == "7+")
    }

    @Test func previousMonthIsTheFinishedOne() throws {
        let month = try #require(ContributionSummary.previousMonth(now: date("2026-01-05T10:00:00Z"), calendar: utc))
        #expect(month.label == "2025-12")
        #expect(month.lastDay - month.firstDay == 30)
        let feb = try #require(ContributionSummary.previousMonth(now: date("2026-03-01T00:30:00Z"), calendar: utc))
        #expect(feb.label == "2026-02")
        #expect(feb.lastDay - feb.firstDay == 27)
    }
}

@Suite struct ContributionSummaryTests {
    private let key = UUID()
    private let month = (label: "2026-11", firstDay: ScoreCalculator.dayNumber(date("2026-11-01T12:00:00Z"), calendar: utc),
                         lastDay: ScoreCalculator.dayNumber(date("2026-11-30T12:00:00Z"), calendar: utc))

    private func build(_ sets: [String: [ScoredSet]], inputs: ContributionInputs = inputs) throws -> ContributionPayload? {
        let model = ScoringModel(model: try EmbeddedModelBundle.model(), version: "v-test")
        return ContributionSummary.build(key: key, inputs: inputs, sets: sets, model: model, month: month, calendar: utc)
    }

    @Test func bandsTheBodyAndKeepsBestSetOfTheMonth() throws {
        let d = month.firstDay
        let payload = try #require(try build([bench: [
            sets(day: d + 2, weight: 50, reps: 5), sets(day: d + 9, weight: 60, reps: 5), sets(day: d + 9, weight: 20, reps: 10, warmup: true),
            sets(day: d - 3, weight: 200, reps: 1), sets(day: month.lastDay + 2, weight: 200, reps: 1)
        ]]))
        #expect(payload.contributionKey == key)
        #expect(payload.sex == "female")
        #expect(payload.ageBand == 30)  // 30 on 2026-11-30
        #expect(payload.bodyweightKg == 64)
        #expect(payload.heightBand == 165)
        #expect(payload.experienceBand == "two_to_5_years")
        #expect(payload.frequencyBand == "3-4")
        #expect(payload.month == "2026-11")
        #expect(payload.modelVersion == "v-test")
        let lift = try #require(payload.lifts.first)
        #expect(payload.lifts.count == 1)
        #expect(lift.exerciseId == bench)
        #expect(lift.bestSetReps == 5)
        #expect(lift.sessionsInMonth == 2, "sets outside the month and warm-up days do not count")
        #expect(lift.bestE1rmKg > 60 && lift.bestE1rmKg < 80)
        #expect(lift.bestE1rmKg == (lift.bestE1rmKg * 10).rounded() / 10)
    }

    @Test func nothingForUnspecifiedSexUnscorableLiftsOrOtherMonths() throws {
        let d = month.firstDay
        var unspecified = inputs
        unspecified.sex = .unspecified
        #expect(try build([bench: [sets(day: d, weight: 60, reps: 5)]], inputs: unspecified) == nil)
        #expect(try build(["not-a-scored-exercise": [sets(day: d, weight: 60, reps: 5)]]) == nil)
        #expect(try build([bench: [sets(day: d - 40, weight: 60, reps: 5)]]) == nil)
        #expect(try build([bench: [sets(day: d, weight: 60, reps: 5, warmup: true)]]) == nil)
    }

    @Test func lowConfidenceHighRepSetsAreLeftOut() throws {
        let d = month.firstDay
        #expect(try build([bench: [sets(day: d, weight: 20, reps: 40)]]) == nil)
    }

    @Test func payloadCarriesNoIdentityFields() throws {
        let payload = try #require(try build([bench: [sets(day: month.firstDay, weight: 60, reps: 5)]]))
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        for forbidden in ["user_id", "userId", "email", "name", "birth"] { #expect(!json.contains(forbidden), "\(forbidden)") }
        #expect(json.contains("contribution_key"))
    }
}

// MARK: Service

private final class RecordingTransport: ContributionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sent: [ContributionPayload] = []
    private(set) var deleted: [UUID] = []
    var failDelete = false

    func send(_ payload: ContributionPayload) async throws { lock.withLock { sent.append(payload) } }

    func delete(contributionKey: UUID) async throws {
        if failDelete { throw ContributionError.failed }
        lock.withLock { deleted.append(contributionKey) }
    }
}

private struct FixedSource: ContributionDataSource {
    var available = true

    func summary(userId: UUID, key: UUID, month: (label: String, firstDay: Int, lastDay: Int)) async -> ContributionPayload? {
        available ? ContributionPayload(
            contributionKey: key, sex: "male", ageBand: 25, bodyweightKg: 80, heightBand: 180, experienceBand: "none", frequencyBand: "3-4",
            month: month.label, modelVersion: "v", lifts: [.init(exerciseId: bench, bestE1rmKg: 90, bestSetReps: 5, sessionsInMonth: 4)]
        ) : nil
    }
}

@Suite struct ContributionServiceTests {
    private let clock = LockedDate(date("2026-12-05T10:00:00Z"))
    private let transport = RecordingTransport()
    private let keys = InMemoryContributionKeyStore()
    private let state = UserDefaultsContributionStateStore(defaults: UserDefaults(suiteName: "contribution-tests-\(UUID().uuidString)")!)

    private func make(source: FixedSource = FixedSource()) throws -> (ContributionService, ConsentService) {
        let testClock = TestClock()
        let consents = ConsentService(repository: try SwiftDataConsentRepository(modelContainer: DataStore.inMemory(), clock: testClock.closure))
        let date = clock
        return (ContributionService(
            consents: consents, keys: keys, state: state, transport: transport, data: source, clock: { date.value }, calendar: utc
        ), consents)
    }

    @Test func neverSendsWithoutConsent() async throws {
        let (service, consents) = try make()
        #expect(try await service.sendIfDue(userId: testUser) == .noConsent)  // not asked
        try await consents.setContribution(false, userId: testUser)
        #expect(try await service.sendIfDue(userId: testUser) == .noConsent)  // declined
        #expect(transport.sent.isEmpty)
        #expect(keys.current(userId: testUser) == nil, "no key is created without consent")
    }

    @Test func sendsOncePerMonthWithAStableKey() async throws {
        let (service, consents) = try make()
        try await consents.setContribution(true, userId: testUser)
        #expect(try await service.sendIfDue(userId: testUser) == .sent(month: "2026-11"))
        #expect(try await service.sendIfDue(userId: testUser) == .notDue)
        #expect(transport.sent.count == 1)
        clock.value = date("2027-01-03T10:00:00Z")
        #expect(try await service.sendIfDue(userId: testUser) == .sent(month: "2026-12"))
        #expect(Set(transport.sent.map(\.contributionKey)).count == 1, "the same key within 12 months")
    }

    @Test func keyRotatesAfterTwelveMonths() async throws {
        let (service, consents) = try make()
        try await consents.setContribution(true, userId: testUser)
        _ = try await service.sendIfDue(userId: testUser)
        clock.value = date("2027-12-05T10:00:00Z")
        _ = try await service.sendIfDue(userId: testUser)
        #expect(Set(transport.sent.map(\.contributionKey)).count == 2)
    }

    @Test func nothingToSendKeepsTheMonthOpen() async throws {
        let (service, consents) = try make(source: FixedSource(available: false))
        try await consents.setContribution(true, userId: testUser)
        #expect(try await service.sendIfDue(userId: testUser) == .nothingToSend)
        #expect(transport.sent.isEmpty)
    }

    @Test func withdrawalDeletesServerRowsAndDestroysTheKey() async throws {
        let (service, consents) = try make()
        try await consents.setContribution(true, userId: testUser)
        _ = try await service.sendIfDue(userId: testUser)
        let key = try #require(keys.current(userId: testUser)?.key)
        try await service.withdraw(userId: testUser)
        #expect(transport.deleted == [key])
        #expect(keys.current(userId: testUser) == nil)
        #expect(state.lastSent(userId: testUser) == nil)
    }

    @Test func failedDeletionKeepsTheKeyForRetry() async throws {
        let (service, consents) = try make()
        try await consents.setContribution(true, userId: testUser)
        _ = try await service.sendIfDue(userId: testUser)
        transport.failDelete = true
        await #expect(throws: ContributionError.self) { try await service.withdraw(userId: testUser) }
        #expect(keys.current(userId: testUser) != nil)
    }

    @Test func previewShowsWhatWasSentOrWouldBe() async throws {
        let (service, consents) = try make()
        let before = try #require(await service.lastMonthPreview(userId: testUser))
        #expect(!before.wasSent)
        try await consents.setContribution(true, userId: testUser)
        _ = try await service.sendIfDue(userId: testUser)
        let after = try #require(await service.lastMonthPreview(userId: testUser))
        #expect(after.wasSent)
        #expect(after.payload.readableJSON().contains("\"month\" : \"2026-11\""))
    }
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ value: Date) { stored = value }
    var value: Date { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
}
