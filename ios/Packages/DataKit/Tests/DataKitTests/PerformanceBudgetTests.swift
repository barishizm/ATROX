@testable import DataKit
import Foundation
import StrengthKit
import SwiftData
import Testing

/// Performance budgets (P098). Each measurement is the median of several runs, compared to a budget that is
/// 5-10x the number measured on a development Mac, so a slow CI runner does not flake but an accidental
/// O(n²) or a main-thread-sized regression does. Measured numbers and device targets: `docs/PERFORMANS.md`.
@Suite struct PerformanceBudgetTests {
    private func median(runs: Int = 5, _ body: () async throws -> Void) async rethrows -> Duration {
        var samples: [Duration] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let start = clock.now
            try await body()
            samples.append(start.duration(to: clock.now))
        }
        return samples.sorted()[runs / 2]
    }

    private func realPackage() throws -> CatalogPackage {
        try CatalogPackage.decode(Data(contentsOf: realCatalogURL, options: .mappedIfSafe))
    }

    @Test func catalogDecodeStaysUnderBudget() async throws {
        let time = try await median { _ = try realPackage() }
        print("PERF decode: \(time)"); #expect(time < .milliseconds(500), "decode took \(time)")
    }

    @Test func upToDateBootstrapSkipsDecoding() async throws {
        let container = try DataStore.inMemory()
        let package = try realPackage()
        try await CatalogImporter(modelContainer: container)
            .apply(package.exercises, mode: .full, version: package.version, checksum: package.checksum)
        let version = package.version
        // The loader throws: the up-to-date path must answer from the file name alone.
        let current = CatalogService(
            modelContainer: container, bundled: { throw CatalogError.bundledCatalogMissing }, bundledVersion: { version })
        #expect(try await current.bootstrap() == .upToDate(version: version))
        // A newer bundled file is still decoded and imported.
        let newer = CatalogService(modelContainer: container, bundled: { throw CatalogError.bundledCatalogMissing }, bundledVersion: { version + 1 })
        await #expect(throws: CatalogError.self) { try await newer.bootstrap() }
    }

    @Test func firstCatalogImportStaysUnderBudget() async throws {
        let package = try realPackage()
        let time = try await median(runs: 3) {
            let importer = CatalogImporter(modelContainer: try DataStore.inMemory())
            try await importer.apply(package.exercises, mode: .full, version: package.version, checksum: package.checksum)
        }
        print("PERF import: \(time)"); #expect(time < .seconds(3), "import took \(time)")
    }

    @Test func librarySearchOverLargeCatalogStaysUnderBudget() async throws {
        let package = try realPackage()
        let container = try DataStore.inMemory()
        try await CatalogImporter(modelContainer: container)
            .apply(package.exercises, mode: .full, version: package.version, checksum: package.checksum)
        let items = try ModelContext(container).fetch(FetchDescriptor<Exercise>()).map(ExerciseListItem.init)
        // The real catalog already has 800+ rows (the library's design size); a second copy checks it scales linearly.
        let scaled = (0..<2).flatMap { copy in
            items.map { item in
                ExerciseListItem(
                    id: "\(item.id)-\(copy)", nameEn: item.nameEn, nameTr: item.nameTr,
                    primaryMuscles: item.primaryMuscles, equipment: item.equipment, isScorable: item.isScorable)
            }
        }
        #expect(scaled.count >= 1_600)
        let time = await median { for query in ["bench", "sq", "pazi", "romanian dead"] { _ = ExerciseSearch.rank(query: query, in: scaled) } }
        print("PERF library search x4 over \(scaled.count): \(time)")
        #expect(time < .milliseconds(400), "4 searches over \(scaled.count) items took \(time)")
    }

    @Test func historyPageOver500WorkoutsStaysUnderBudget() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: clock.now) }
        for draft in TrainingFixtures.largeHistory(count: 520, now: clock.now) { try await repo.start(draft, userId: testUser) }
        let time = try await median { _ = try await repo.finishedWorkouts(userId: testUser, before: nil, limit: 30) }
        print("PERF history page: \(time)"); #expect(time < .milliseconds(500), "first page took \(time)")
    }

    @Test func scoreRefreshOverLongHistoryStaysUnderBudget() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let model = try EmbeddedModelBundle.model()
        let service = ScoreService(
            modelContainer: container, scoringModel: { ScoringModel(model: model, version: "1.0.0") }, clock: clock.closure,
            calendar: Calendar(identifier: .gregorian))
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: clock.now) }
        for draft in TrainingFixtures.largeHistory(count: 520, now: clock.now) { try await repo.start(draft, userId: testUser) }
        let first = try await timed { _ = await service.refresh(userId: testUser) }
        print("PERF score full: \(first)"); #expect(first < .seconds(5), "full score computation took \(first)")
        // An unchanged history still re-reads and diffs every finished set (~the cost of a full pass); it runs off the main actor.
        let unchanged = await median { _ = await service.refresh(userId: testUser) }
        print("PERF score no-change: \(unchanged)"); #expect(unchanged < .seconds(1), "no-change refresh took \(unchanged)")
    }

    @Test func trainingReadsOverLongHistoryStayUnderBudget() async throws {
        let container = try DataStore.inMemory()
        let clock = TestClock()
        let repo = SwiftDataWorkoutRepository(modelContainer: container, clock: clock.closure)
        let model = try EmbeddedModelBundle.model()
        let service = ScoreService(
            modelContainer: container, scoringModel: { ScoringModel(model: model, version: "1.0.0") }, clock: clock.closure,
            calendar: Calendar(identifier: .gregorian))
        try await MainActor.run { try DataFixtures.seed(container, userId: testUser, now: clock.now) }
        for draft in TrainingFixtures.largeHistory(count: 520, now: clock.now) { try await repo.start(draft, userId: testUser) }
        _ = await service.refresh(userId: testUser)
        let stats = TrainingStats(modelContainer: container, clock: clock.closure, calendar: Calendar(identifier: .gregorian))
        let dashboard = await median { _ = await stats.dashboard(userId: testUser, population: .gym, overallScore: nil) }
        print("PERF dashboard: \(dashboard)"); #expect(dashboard < .seconds(1), "dashboard took \(dashboard)")
        let insights = InsightService(
            modelContainer: container, scores: service, stats: stats, clock: clock.closure, calendar: Calendar(identifier: .gregorian))
        let refresh = await median { _ = await insights.refresh(userId: testUser) }
        print("PERF insights.refresh: \(refresh)"); #expect(refresh < .seconds(2), "insights.refresh took \(refresh)")
        let muscles = await median { _ = await stats.muscleReport(userId: testUser) }
        print("PERF muscleReport: \(muscles)"); #expect(muscles < .seconds(1), "muscleReport took \(muscles)")
        let recent = try await median { _ = try await repo.recentExercises(userId: testUser, limit: 12) }
        print("PERF recentExercises: \(recent)"); #expect(recent < .seconds(1), "recentExercises took \(recent)")
        let dates = try await median { _ = try await repo.finishedDates(userId: testUser) }
        print("PERF finishedDates: \(dates)"); #expect(dates < .seconds(1), "finishedDates took \(dates)")
        let exercise = try #require(try await repo.finishedWorkouts(userId: testUser, before: nil, limit: 1).first?.exercises.first?.ref)
        let history = try await median { _ = try await repo.history(userId: testUser, ref: exercise, limit: 10) }
        print("PERF exerciseHistory: \(history)"); #expect(history < .seconds(1), "exerciseHistory took \(history)")
    }

    private func timed(_ body: () async throws -> Void) async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try await body()
        return start.duration(to: clock.now)
    }
}
