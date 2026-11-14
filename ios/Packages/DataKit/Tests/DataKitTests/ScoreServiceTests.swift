@testable import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

private let bench = "barbell-bench-press-medium-grip"

private struct ScoreEnv {
    let container: ModelContainer
    let clock = TestClock()
    let workouts: SwiftDataWorkoutRepository
    let version = LockedBox("1.0.0")
    let service: ScoreService

    init(seedHistory: Bool = true) async throws {
        container = try DataStore.inMemory()
        let now = clock.now
        let box = version
        let model = try EmbeddedModelBundle.model()
        workouts = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        service = ScoreService(
            modelContainer: container, scoringModel: { ScoringModel(model: model, version: box.value) }, clock: clock.closure,
            calendar: Calendar(identifier: .gregorian)
        )
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: now) }
        if seedHistory {
            for draft in TrainingFixtures.twelveWeekHistory(now: now) { try await workouts.start(draft, userId: testUser) }
        }
    }

    func addWorkout(_ id: String, weight: Double, reps: Int, daysAgo: Int = 0) async throws {
        let start = clock.now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600)
        let sets = [SetInput(weightKg: weight, reps: reps, rir: 1, setType: .working, isCompleted: true)]
        _ = try await workouts.start(
            WorkoutDraft(startedAt: start, endedAt: start.addingTimeInterval(1_800), exercises: [WorkoutExerciseDraft(ref: .catalog(id), sets: sets)]),
            userId: testUser
        )
    }

    func snapshots() throws -> [ScoreSnapshot] {
        try ModelContext(container).fetch(FetchDescriptor<ScoreSnapshot>())
    }
}

private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String
    init(_ value: String) { stored = value }
    var value: String { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
}

private func ready(_ outcome: ScoreOutcome) throws -> ScoreOverview {
    guard case .ready(let overview) = outcome else { throw Failure.notReady(outcome) }
    return overview
}

private enum Failure: Error { case notReady(ScoreOutcome) }

@Suite struct ScoreServiceTests {
    @Test func scoresTheHistoryAndAggregatesGroups() async throws {
        let env = try await ScoreEnv()
        let overview = try ready(await env.service.overview(userId: testUser))
        let score = try #require(overview.exercises[bench])
        #expect((1...99).contains(score.score.score))
        #expect(score.basis != nil)
        #expect(overview.overall != nil)
        #expect(overview.muscles["chest"] != nil)
    }

    @Test func incrementalEqualsFullAfterAWorkoutAndAfterAnEdit() async throws {
        let env = try await ScoreEnv()
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)  // warm the cache
        // A believable step up (a bigger jump would wait for the user's confirmation as an outlier).
        try await env.addWorkout(bench, weight: 77.5, reps: 6)
        let incremental = try ready(await env.service.recalculate(userId: testUser, trigger: .exercises([bench])))
        await env.service.reset()
        let full = try ready(await env.service.recalculate(userId: testUser, trigger: .everything))
        #expect(incremental == full)
        #expect(incremental.exercises[bench]?.basis?.weightKg == 77.5)

        // Edit: remove that workout's set → back to the earlier strength, still equal to a full pass.
        let finished = try await env.workouts.finishedWorkouts(userId: testUser, before: nil, limit: 1)
        let newest = try #require(finished.first)
        try await env.workouts.delete(id: newest.id)
        let afterDelete = try ready(await env.service.recalculate(userId: testUser, trigger: .exercises([bench])))
        await env.service.reset()
        #expect(afterDelete == (try ready(await env.service.recalculate(userId: testUser, trigger: .everything))))
        #expect(afterDelete.exercises[bench]?.basis?.weightKg != 77.5)
    }

    @Test func refreshOnlyWorksWhenSomethingScoreRelevantChanged() async throws {
        let env = try await ScoreEnv()
        #expect(await env.service.refresh(userId: testUser) != nil)  // first run computes
        #expect(await env.service.refresh(userId: testUser) == nil)  // nothing changed
        try await env.addWorkout(bench, weight: 77.5, reps: 6)
        let after = try ready(try #require(await env.service.refresh(userId: testUser)))
        #expect(after.exercises[bench]?.basis?.weightKg == 77.5)
        await env.service.reset()
        #expect(after == (try ready(await env.service.recalculate(userId: testUser, trigger: .everything))))
        // A new weigh-in changes everyone's scores.
        let context = ModelContext(env.container)
        context.insert(BodyMeasurement(userId: testUser, input: MeasurementInput(date: env.clock.now.addingTimeInterval(60), weightKg: 95), now: env.clock.now))
        try context.save()
        #expect(await env.service.refresh(userId: testUser) != nil)
        // A new model version too.
        env.version.value = "1.2.0"
        #expect(await env.service.refresh(userId: testUser) != nil)
        #expect(await env.service.refresh(userId: testUser) == nil)
    }

    @Test func recalculatingTwiceWritesNoDuplicateSnapshots() async throws {
        let env = try await ScoreEnv()
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)
        let first = try env.snapshots()
        #expect(!first.isEmpty)
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)
        let second = try env.snapshots()
        #expect(second.count == first.count)
        #expect(Set(second.map(\.id)).count == second.count)
        #expect(second.allSatisfy { $0.syncState == .pending })
        #expect(first.contains { $0.scope == .overall && $0.key == "overall" })
        #expect(first.contains { $0.scope == .muscle } && first.contains { $0.scope == .exercise })
    }

    @Test func aChangedScoreUpdatesTodaysSnapshotInPlace() async throws {
        let env = try await ScoreEnv()
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)
        let before = try #require(try env.snapshots().first { $0.key == bench })
        try await env.addWorkout(bench, weight: 77.5, reps: 6)
        _ = await env.service.recalculate(userId: testUser, trigger: .exercises([bench]))
        let rows = try env.snapshots().filter { $0.key == bench }
        #expect(rows.count == 1)
        #expect(rows[0].id == before.id)
        #expect(rows[0].score > before.score)
    }

    @Test func aNewModelVersionRewritesSnapshotsAndKeepsOneRowPerDay() async throws {
        let env = try await ScoreEnv()
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)
        let count = try env.snapshots().count
        env.version.value = "1.1.0"
        _ = await env.service.recalculate(userId: testUser, trigger: .everything)
        let rows = try env.snapshots()
        #expect(rows.count == count)
        #expect(rows.allSatisfy { $0.modelVersion == "1.1.0" })
    }

    @Test func backfillCreatesWeeklySnapshotsOnceAndSeriesIsOrdered() async throws {
        let env = try await ScoreEnv()
        await env.service.backfillIfNeeded(userId: testUser)
        let series = await env.service.history(userId: testUser, scope: .exercise, key: bench, population: .gym)
        #expect(series.count >= 8)
        #expect(series.map(\.date) == series.map(\.date).sorted())
        // Strength grows through the fixture history, so the series must not fall overall.
        #expect(try #require(series.last).score >= #require(series.first).score)
        let count = try env.snapshots().count
        await env.service.backfillIfNeeded(userId: testUser)
        #expect(try env.snapshots().count == count)
        let overall = await env.service.history(userId: testUser, scope: .overall, key: "overall", population: .gym)
        #expect(!overall.isEmpty)
    }

    @Test func referenceGroupChangesTheScoreWithoutStoring() async throws {
        let env = try await ScoreEnv()
        let gym = try #require(await env.service.evaluation(userId: testUser, exerciseId: bench, population: .gym))
        let general = try #require(await env.service.evaluation(userId: testUser, exerciseId: bench, population: .general))
        let competitor = try #require(await env.service.evaluation(userId: testUser, exerciseId: bench, population: .competitor))
        #expect(gym.score.score != general.score.score)
        #expect(competitor.score.score < gym.score.score)
        #expect(try env.snapshots().isEmpty)
    }

    @Test func onboardingSquatCountsForTheAnchorSquat() async throws {
        let env = try await ScoreEnv(seedHistory: false)
        try await env.addWorkout("barbell-squat", weight: 100, reps: 5)
        let overview = try ready(await env.service.overview(userId: testUser))
        #expect(overview.exercises["barbell-full-squat"]?.basis?.weightKg == 100)
        #expect(overview.exercises["barbell-squat"] == nil)
    }

    @Test func unavailableWithoutProfileOrWeight() async throws {
        let env = try await ScoreEnv(seedHistory: false)
        let ghost = UUID()
        #expect(await env.service.overview(userId: ghost) == .unavailable(.noProfile))
        let context = ModelContext(env.container)
        context.insert(UserProfile(userId: ghost, input: DataFixtures.profileInput(now: env.clock.now), now: env.clock.now))
        try context.save()
        #expect(await env.service.overview(userId: ghost) == .unavailable(.noBodyweight))
    }

    @Test func bodyweightGetsStaleAfterSixtyDays() async throws {
        let env = try await ScoreEnv(seedHistory: false)
        #expect(await env.service.bodyweight(userId: testUser)?.isStale == false)
        env.clock.advance(by: 61 * 86_400)
        #expect(await env.service.bodyweight(userId: testUser)?.isStale == true)
    }

    @Test func snapshotIdIsDeterministicAndSurvivesTheSyncDTO() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ScoreSnapshot(userId: testUser, scope: .muscle, key: "chest", referenceGroup: "gym", score: 61.5, z: 0.29, confidence: "medium", modelVersion: "1.0.0", date: day)
        let second = ScoreSnapshot(
            userId: testUser, scope: .muscle, key: "chest", referenceGroup: "gym", score: 10, z: -1.2, confidence: "low",
            modelVersion: "1.0.1", date: day.addingTimeInterval(3_600)
        )
        #expect(first.id == second.id)
        #expect(first.id != ScoreSnapshot(userId: testUser, scope: .muscle, key: "chest", referenceGroup: "general", score: 1, z: 0, confidence: "low", modelVersion: "1", date: day).id)
        let copy = ScoreSnapshot(syncDTO: first.makeDTO())
        #expect(copy.id == first.id && copy.score == 61.5 && copy.key == "chest" && copy.syncState == .synced)
    }

    @Test func insightHasDistributionTargetAndConsistentGroups() async throws {
        let env = try await ScoreEnv()
        var scores: [ReferencePopulation: Double] = [:]
        for group in ReferencePopulation.allCases {
            let insight = try #require(await env.service.insight(userId: testUser, exerciseId: bench, population: group))
            let evaluation = try #require(insight.evaluation)
            scores[group] = evaluation.score.score
            #expect(insight.notScorable == nil && insight.distribution?.points.isEmpty == false)
            #expect(evaluation.score.population == group)
            let band = try #require(insight.bandE1RMKg)
            #expect(band.contains(try #require(evaluation.strength.e1rmKg)))
            if let target = insight.nextTarget {
                #expect(target.minScore > evaluation.score.score && target.gapKg > 0)
                #expect(insight.targetLoads.map(\.reps) == ScoreService.targetReps)
                // Fewer reps need a heavier load.
                #expect(insight.targetLoads.map(\.weightKg) == insight.targetLoads.map(\.weightKg).sorted(by: >))
            }
        }
        // The insight agrees with the stored overview of the preferred group.
        let overview = try ready(await env.service.overview(userId: testUser, population: .gym))
        #expect(overview.exercises[bench]?.score.score == scores[.gym])
        #expect(try #require(scores[.competitor]) < #require(scores[.gym]))
    }

    @Test func insightExplainsMissingScores() async throws {
        let env = try await ScoreEnv(seedHistory: false)
        #expect(await env.service.insight(userId: testUser, exerciseId: UUID().uuidString, population: .gym)?.notScorable == .notInModel)
        #expect(await env.service.insight(userId: testUser, exerciseId: bench, population: .gym)?.notScorable == .noData)
        try await env.addWorkout(bench, weight: 60, reps: 8)
        let one = try #require(await env.service.insight(userId: testUser, exerciseId: bench, population: .gym))
        #expect(one.evaluation != nil)
        #expect(one.reasons.contains(.fewSessions))
    }
}
