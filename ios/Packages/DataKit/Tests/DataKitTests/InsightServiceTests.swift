@testable import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

private let bench = "barbell-bench-press-medium-grip"

private struct InsightEnv {
    let container: ModelContainer
    let clock = TestClock()
    let workouts: SwiftDataWorkoutRepository
    let service: InsightService

    init() async throws {
        container = try DataStore.inMemory()
        let now = clock.now
        let model = try EmbeddedModelBundle.model()
        let calendar = Calendar(identifier: .gregorian)
        workouts = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let scores = ScoreService(
            modelContainer: container, scoringModel: { ScoringModel(model: model, version: "1.0.0") }, clock: clock.closure, calendar: calendar
        )
        let stats = TrainingStats(modelContainer: container, clock: clock.closure, calendar: calendar)
        service = InsightService(modelContainer: container, scores: scores, stats: stats, clock: clock.closure, calendar: calendar)
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: now) }
        for draft in TrainingFixtures.twelveWeekHistory(now: now) { try await workouts.start(draft, userId: testUser) }
    }

    func records() throws -> [InsightRecord] {
        try ModelContext(container).fetch(FetchDescriptor<InsightRecord>())
    }

    func trainToday() async throws {
        let start = clock.now.addingTimeInterval(-3_600)
        let sets = [SetInput(weightKg: 60, reps: 8, rir: 2, setType: .working, isCompleted: true)]
        _ = try await workouts.start(
            WorkoutDraft(startedAt: start, endedAt: start.addingTimeInterval(1_800), exercises: [WorkoutExerciseDraft(ref: .catalog(bench), sets: sets)]),
            userId: testUser
        )
    }
}

@Suite struct InsightServiceTests {
    @Test func aLongBreakProducesOneStoredInsightAndRefreshingDoesNotDuplicateIt() async throws {
        let env = try await InsightEnv()
        env.clock.advance(by: 40 * 86_400)
        let first = await env.service.refresh(userId: testUser)
        let comeback = try #require(first.first { $0.kind == .comeback })
        #expect(comeback.isActive && comeback.payload.values["days"] ?? 0 >= 30)
        let count = try env.records().count
        _ = await env.service.refresh(userId: testUser)
        _ = await env.service.refresh(userId: testUser)
        #expect(try env.records().count == count)
        #expect(Set(try env.records().map(\.id)).count == count)
        #expect(try env.records().allSatisfy { $0.syncState == .pending })
    }

    @Test func showingStartsTheRepeatPauseAndDismissingIsRemembered() async throws {
        let env = try await InsightEnv()
        env.clock.advance(by: 40 * 86_400)
        _ = await env.service.refresh(userId: testUser)
        let top = try #require(await env.service.topForToday(userId: testUser))
        #expect(top.lastShownAt != nil)
        // Same day: the card stays; next day: it rests for two weeks and another one (or none) takes over.
        #expect(await env.service.topForToday(userId: testUser)?.id == top.id)
        env.clock.advance(by: 86_400)
        _ = await env.service.refresh(userId: testUser)
        #expect(await env.service.topForToday(userId: testUser)?.id != top.id)
        await env.service.dismiss(id: top.id)
        _ = await env.service.refresh(userId: testUser)
        #expect(await env.service.current(userId: testUser).contains { $0.id == top.id } == false)
        #expect(await env.service.history(userId: testUser).contains { $0.id == top.id })
        let stored = try #require(try env.records().first { $0.id == top.id })
        #expect(stored.dismissedAt != nil)
    }

    @Test func anInsightBecomesInactiveWhenItsConditionIsGone() async throws {
        let env = try await InsightEnv()
        env.clock.advance(by: 40 * 86_400)
        _ = await env.service.refresh(userId: testUser)
        #expect(await env.service.current(userId: testUser).contains { $0.kind == .comeback })
        try await env.trainToday()
        _ = await env.service.refresh(userId: testUser)
        #expect(await env.service.current(userId: testUser).contains { $0.kind == .comeback } == false)
        #expect(try env.records().first { $0.kindRaw == "comeback" }?.isActive == false)
    }

    @Test func insightRowsKeepTheirIdAndFieldsThroughTheSyncDTO() throws {
        let payload = InsightPayload(subjects: ["lats"], muscles: ["lats"], values: ["weekly_average": 8], variant: "")
        let record = InsightRecord(
            userId: testUser, kind: .neglectedMuscle, subject: "lats", severity: .moderate, priority: 66.25, action: .suggestExercises,
            payload: payload, detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        record.dismissedAt = Date(timeIntervalSince1970: 1_800_100_000)
        #expect(record.id == InsightRecord.id(userId: testUser, kind: "neglected_muscle", subject: "lats"))
        #expect(record.id != InsightRecord.id(userId: testUser, kind: "neglected_muscle", subject: "calves"))
        let copy = InsightRecord(syncDTO: record.makeDTO())
        #expect(copy.id == record.id && copy.insight == record.insight && copy.syncState == .synced)
        #expect(copy.insight?.payload == payload && copy.insight?.dismissedAt == record.dismissedAt)
    }
}
