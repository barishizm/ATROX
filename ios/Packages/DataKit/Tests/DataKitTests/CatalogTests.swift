@testable import DataKit
import Foundation
import SwiftData
import Testing

// MARK: - Fixtures

private func record(
    _ id: String, en: String? = nil, tr: String? = nil, aliases: [String] = [], archived: Bool = false
) -> CatalogRecord {
    CatalogRecord(
        id: id, equipment: "barbell", level: "beginner", category: "strength", primaryMuscles: ["chest"],
        movementPattern: "horizontal_push", scoringType: "weighted", isCore: true, images: ["\(id)-1.f.webp"],
        translations: [
            "en": .init(name: en ?? "EN \(id)", aliases: aliases, instructions: ["Do it."]),
            "tr": .init(name: tr ?? "TR \(id)", aliases: [], instructions: ["Yap."]),
        ],
        archived: archived
    )
}

private func package(_ version: Int, _ records: [CatalogRecord]) -> CatalogPackage {
    CatalogPackage(version: version, checksum: "sum\(version)", exercises: records)
}

private struct FakeRemote: CatalogRemote {
    var versions: [CatalogVersionInfo]
    var changed: [CatalogRecord]

    func latestVersion() async throws -> CatalogVersionInfo? { versions.max { $0.version < $1.version } }
    func version(_ number: Int) async throws -> CatalogVersionInfo? { versions.first { $0.version == number } }
    func changes(since: String) async throws -> [CatalogRecord] { changed }
}

private func exercises(in container: ModelContainer) throws -> [Exercise] {
    try ModelContext(container).fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.id)]))
}

// MARK: - Folding and file naming

@Suite struct SearchFoldingTests {
    @Test func foldsTurkishAndAccentedText() {
        #expect(SearchFolding.fold("Şınav") == "sinav")
        #expect(SearchFolding.fold("ÇEKİŞ") == "cekis")
        #expect(SearchFolding.fold("IŞIK İnce") == "isik ince")
        #expect(SearchFolding.fold("Göğüs Pres") == "gogus pres")
        #expect(SearchFolding.fold("Crème Brûlée") == "creme brulee")
    }

    @Test func thumbnailNameFollowsTheImagePipelineConvention() {
        #expect(ImageNaming.thumb(forFull: "eada9a6c8f1aeb7c.f.webp") == "eada9a6c8f1aeb7c.t.webp")
        #expect(ImageNaming.thumb(forFull: "other.png") == "other.png")
    }

    @Test func bundledFileNamesParseTheirVersion() {
        #expect(BundledCatalog.version(ofFileNamed: "catalog.v12.json") == 12)
        #expect(BundledCatalog.version(ofFileNamed: "catalog.json") == nil)
        #expect(BundledCatalog.version(ofFileNamed: "exercises.v1.json") == nil)
    }
}

// MARK: - Package decoding

@Suite struct CatalogPackageTests {
    @Test func decodesTheRealBundledCatalog() throws {
        let catalog = try CatalogPackage.decode(Data(contentsOf: realCatalogURL))
        #expect(catalog.version >= 1)
        #expect(catalog.exercises.count == 876)
        #expect(Set(catalog.exercises.map(\.id)).count == 876)
        let bench = try #require(catalog.exercises.first { $0.id == "barbell-bench-press-medium-grip" })
        #expect(bench.primaryMuscles == ["chest"])
        #expect(bench.translations["tr"]?.name.isEmpty == false)
        #expect(bench.translations["en"]?.instructions.isEmpty == false)
        #expect(catalog.exercises.allSatisfy { $0.translations["en"] != nil && $0.translations["tr"] != nil })
        #expect(catalog.exercises.contains { !$0.images.isEmpty })
        #expect(catalog.exercises.contains { $0.isCore })
    }

    @Test func rejectsAFormatNewerThanTheApp() {
        let json = #"{"format":99,"version":1,"checksum":"x","exercises":[]}"#
        #expect(throws: CatalogError.unsupportedFormat(99)) { try CatalogPackage.decode(Data(json.utf8)) }
    }
}

// MARK: - Import, version upgrade, archiving

@Suite struct CatalogServiceTests {
    @Test func firstLaunchImportsTheBundledCatalogOnce() async throws {
        let container = try DataStore.inMemory()
        let pkg = package(1, [record("a"), record("b")])
        let service = CatalogService(modelContainer: container, bundled: { pkg })

        #expect(try await service.installedVersion() == nil)
        #expect(try await service.bootstrap() == .imported(version: 1, count: 2))
        #expect(try await service.installedVersion() == 1)
        #expect(try await service.bootstrap() == .upToDate(version: 1))
        #expect(try exercises(in: container).map(\.id) == ["a", "b"])
    }

    @Test func importedRowCarriesBothLanguagesAndFoldedSearchText() async throws {
        let container = try DataStore.inMemory()
        let r = record("press", en: "Bench Press", tr: "Göğüs Presi", aliases: ["Şınav"])
        _ = try await CatalogService(modelContainer: container, bundled: { package(1, [r]) }).bootstrap()
        let e = try #require(try exercises(in: container).first)
        #expect(e.name(languageCode: "tr") == "Göğüs Presi" && e.name(languageCode: "en") == "Bench Press")
        #expect(e.searchText.contains("gogus presi") && e.searchText.contains("sinav"))
        #expect(e.isArchived == false && e.imagePaths == ["press-1.f.webp"] && e.scoringTypeRaw == "weighted")
    }

    @Test func newBundledVersionUpdatesInPlaceAndArchivesRemovedExercises() async throws {
        let container = try DataStore.inMemory()
        _ = try await CatalogService(modelContainer: container, bundled: { package(1, [record("a"), record("b")]) })
            .bootstrap()
        let v2 = package(2, [record("a", en: "A renamed"), record("c")])
        let result = try await CatalogService(modelContainer: container, bundled: { v2 }).bootstrap()

        #expect(result == .imported(version: 2, count: 2))
        let all = try exercises(in: container)
        #expect(all.map(\.id) == ["a", "b", "c"])  // b is kept: history may reference it
        #expect(all.first { $0.id == "a" }?.nameEn == "A renamed")
        #expect(all.first { $0.id == "b" }?.isArchived == true)
        #expect(all.first { $0.id == "c" }?.isArchived == false)
    }

    @Test func olderBundledFileNeverDowngrades() async throws {
        let container = try DataStore.inMemory()
        _ = try await CatalogService(modelContainer: container, bundled: { package(3, [record("a")]) }).bootstrap()
        let result = try await CatalogService(modelContainer: container, bundled: { package(2, [record("zzz")]) })
            .bootstrap()
        #expect(result == .upToDate(version: 3))
        #expect(try exercises(in: container).map(\.id) == ["a"])
    }

    @Test func remoteSyncAppliesOnlyTheDifferenceWhenTheServerIsNewer() async throws {
        let container = try DataStore.inMemory()
        _ = try await CatalogService(modelContainer: container, bundled: { package(1, [record("a"), record("b")]) })
            .bootstrap()
        let remote = FakeRemote(
            versions: [.init(version: 1, checksum: "sum1", publishedAt: "2026-11-01T00:00:00+00:00"),
                       .init(version: 2, checksum: "sum2", publishedAt: "2026-11-10T00:00:00+00:00")],
            changed: [record("b", en: "B fixed"), record("a", archived: true), record("d")]
        )
        let service = CatalogService(modelContainer: container, bundled: { package(1, []) }, remote: remote)

        #expect(try await service.syncRemote() == .updated(from: 1, to: 2, changed: 3))
        let all = try exercises(in: container)
        #expect(all.map(\.id) == ["a", "b", "d"])
        #expect(all.first { $0.id == "b" }?.nameEn == "B fixed")
        #expect(all.first { $0.id == "a" }?.isArchived == true)
        #expect(try await service.installedVersion() == 2)
        #expect(try await service.syncRemote() == .upToDate(version: 2))  // second call: nothing newer
    }

    @Test func deltaSyncLeavesExercisesTheServerDidNotMentionAlone() async throws {
        let container = try DataStore.inMemory()
        _ = try await CatalogService(modelContainer: container, bundled: { package(1, [record("a"), record("b")]) })
            .bootstrap()
        let remote = FakeRemote(
            versions: [.init(version: 1, checksum: "sum1", publishedAt: "t1"), .init(version: 2, checksum: "s", publishedAt: "t2")],
            changed: []
        )
        _ = try await CatalogService(modelContainer: container, remote: remote).syncRemote()
        #expect(try exercises(in: container).allSatisfy { !$0.isArchived })
    }

    @Test func syncBeforeBootstrapAndWithoutRemoteDoNothing() async throws {
        let container = try DataStore.inMemory()
        let remote = FakeRemote(versions: [.init(version: 5, checksum: "s", publishedAt: "t")], changed: [record("x")])
        #expect(try await CatalogService(modelContainer: container, remote: remote).syncRemote() == .notInstalled)
        #expect(try await CatalogService(modelContainer: container).syncRemote() == .notInstalled)
        #expect(try exercises(in: container).isEmpty)
    }

    @Test func catalogUpdatesNeverTouchUserData() async throws {
        let container = try DataStore.inMemory()
        let measurements = SwiftDataMeasurementRepository(modelContainer: container)
        let saved = try await measurements.add(DataFixtures.measurementInputs(count: 1)[0], userId: testUser)
        _ = try await CatalogService(modelContainer: container, bundled: { package(1, [record("a")]) }).bootstrap()
        _ = try await CatalogService(modelContainer: container, bundled: { package(2, []) }).bootstrap()
        #expect(try await measurements.all(userId: testUser) == [saved])
    }

    @Test func realCatalogImportsFast() async throws {
        let pkg = try CatalogPackage.decode(Data(contentsOf: realCatalogURL))
        // Best of 3 fresh imports: the suite runs in parallel with every other test, so a single
        // wall-clock sample on a shared CI runner measures contention, not the import. A real
        // regression makes every run slow; 3 s is still far below what a broken import would take.
        var timings: [Duration] = []
        for _ in 0..<3 {
            let container = try DataStore.inMemory()
            let service = CatalogService(modelContainer: container, bundled: { pkg })
            timings.append(try await ContinuousClock().measure { _ = try await service.bootstrap() })
            #expect(try exercises(in: container).count == 876)
        }
        let elapsed = try #require(timings.min())
        print("P028 import of \(pkg.exercises.count) exercises: best \(elapsed) of \(timings)")
        #expect(elapsed < .seconds(3), "first-launch import must stay under 3 s, took \(elapsed)")
    }
}

// MARK: - Local schema migration

@Suite struct CatalogMigrationTests {
    private enum V1OnlyPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }

    @Test func existingV1StoreMigratesToV2WithoutLosingUserData() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A store written by the shipped (V1) app.
        do {
            let v1Schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(schema: v1Schema, url: folder.appendingPathComponent("ATROX.store"))
            let v1 = try ModelContainer(for: v1Schema, migrationPlan: V1OnlyPlan.self, configurations: config)
            _ = try await SwiftDataProfileRepository(modelContainer: v1)
                .upsert(DataFixtures.profileInput(), userId: testUser)
        }

        // The new app opens the same file.
        let v2 = try DataStore.onDisk(directory: dir)
        #expect(try await SwiftDataProfileRepository(modelContainer: v2).profile(userId: testUser) != nil)
        let service = CatalogService(modelContainer: v2, bundled: { package(1, [record("a")]) })
        #expect(try await service.bootstrap() == .imported(version: 1, count: 1))
    }
}

// MARK: - Supabase REST remote

@Suite struct SupabaseCatalogRemoteTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var requested: [URL] { lock.withLock { urls } }
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
    }

    private func remote(_ recorder: Recorder, exercises: String, translations: String = "[]") -> SupabaseCatalogRemote {
        SupabaseCatalogRemote(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon") { request in
            let url = try #require(request.url)
            recorder.add(url)
            #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon")
            let table = url.path.split(separator: "/").last!
            let body: String
            switch table {
            case "catalog_versions": body = #"[{"version":4,"checksum":"c4","published_at":"2026-11-12T10:00:00.123456+00:00"}]"#
            case "exercises": body = exercises
            default: body = translations
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func readsLatestVersionAndKeepsTheServerTimestampVerbatim() async throws {
        let rec = Recorder()
        let latest = try #require(try await remote(rec, exercises: "[]").latestVersion())
        #expect(latest == CatalogVersionInfo(version: 4, checksum: "c4", publishedAt: "2026-11-12T10:00:00.123456+00:00"))
        #expect(rec.requested[0].query?.contains("order=version.desc") == true)
    }

    @Test func changesEncodePlusInTimestampsAndJoinTranslations() async throws {
        let rec = Recorder()
        let exercise = #"""
        [{"id":"bench-press","equipment":"barbell","mechanic":null,"force":"push","level":"beginner",
          "category":"strength","primary_muscles":["chest"],"secondary_muscles":[],"movement_pattern":"horizontal_push",
          "scoring_type":"weighted","anchor_lift":null,"load_convention":"total","ratio":0.85,"tau":null,
          "ratio_confidence":null,"bw_fraction":null,"is_core":true,"is_unilateral":false,
          "image_paths":["a.f.webp"],"archived_at":"2026-11-12T09:00:00+00:00"}]
        """#
        let translations = #"""
        [{"exercise_id":"bench-press","locale":"en","name":"Bench Press","aliases":["flat"],"instructions":["Lie."]},
         {"exercise_id":"bench-press","locale":"tr","name":"Göğüs Presi","aliases":[],"instructions":[]}]
        """#
        let rows = try await remote(rec, exercises: exercise, translations: translations)
            .changes(since: "2026-11-01T00:00:00+00:00")

        let first = try #require(rec.requested.first?.absoluteString)
        #expect(first.contains("updated_at=gt.2026-11-01T00%3A00%3A00%2B00%3A00"))
        let row = try #require(rows.first)
        #expect(row.id == "bench-press" && row.archived && row.ratio == 0.85 && row.isCore)
        #expect(row.images == ["a.f.webp"] && row.translations["tr"]?.name == "Göğüs Presi")
        #expect(row.translations["en"]?.aliases == ["flat"])
    }

    @Test func httpErrorsAreReported() async {
        let failing = SupabaseCatalogRemote(baseURL: URL(string: "https://x")!, anonKey: "k") { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: CatalogError.invalidResponse("catalog_versions: HTTP 503")) {
            _ = try await failing.latestVersion()
        }
    }
}
