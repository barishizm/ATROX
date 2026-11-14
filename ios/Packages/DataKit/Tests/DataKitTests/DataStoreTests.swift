@testable import DataKit
import Foundation
import SwiftData
import Testing

@Suite struct DataStoreTests {
    @Test func schemaContainsTheUserModelsAndTheCatalog() {
        let v1 = SchemaV1.models.map { String(describing: $0) }.sorted()
        #expect(v1 == ["BodyMeasurement", "ConsentRecord", "UserProfile", "UserSettings"])
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let v2 = SchemaV2.models.map { String(describing: $0) }.sorted()
        #expect(v2 == ["BodyMeasurement", "CatalogInfo", "ConsentRecord", "Exercise", "UserProfile", "UserSettings"])
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        let v3 = SchemaV3.models.map { String(describing: $0) }.sorted()
        #expect(v3 == ["BodyMeasurement", "CatalogInfo", "ConsentRecord", "CustomExercise", "Exercise", "UserProfile", "UserSettings"])
        #expect(SchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        let v4 = SchemaV4.models.map { String(describing: $0) }.sorted()
        #expect(v4 == (v3 + ["PersonalRecord", "Routine", "RoutineDay", "RoutineExercise", "SetEntry", "Workout", "WorkoutExercise"]).sorted())
        #expect(SchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        let v5 = SchemaV5.models.map { String(describing: $0) }.sorted()
        #expect(v5 == v4)
        #expect(SchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        let v6 = SchemaV6.models.map { String(describing: $0) }.sorted()
        #expect(v6 == (v5 + ["ScoreSnapshot"]).sorted())
        #expect(SchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        let v7 = SchemaV7.models.map { String(describing: $0) }.sorted()
        #expect(v7 == (v6 + ["InsightRecord"]).sorted())
        #expect(SchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(DataMigrationPlan.schemas.count == 7)
        #expect(DataMigrationPlan.stages.count == 6)
    }

    @Test func onDiskStorePersistsAcrossContainers() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = SwiftDataProfileRepository(modelContainer: try DataStore.onDisk(directory: dir))
        let saved = try await first.upsert(DataFixtures.profileInput(), userId: testUser)
        let second = SwiftDataProfileRepository(modelContainer: try DataStore.onDisk(directory: dir))
        #expect(try await second.profile(userId: testUser) == saved)
    }

    @Test func productionFailsWithoutAppGroup() {
        #expect(throws: DataStore.StoreError.appGroupUnavailable("group.invalid.test")) {
            try DataStore.production(appGroupID: "group.invalid.test", resolveContainer: { _ in nil })
        }
    }

    @MainActor
    @Test func settingsDefaultsMatchServerColumnDefaults() throws {
        let settings = UserSettings(userId: testUser)
        #expect(settings.theme == .system)
        #expect(settings.weightUnit == .kg)
        #expect(settings.lengthUnit == .cm)
        #expect(settings.referenceGroup == .gym)
        #expect(settings.rirEnabled)
        #expect(settings.restTimerSeconds == 120)
        #expect(settings.defaultBarKg == 20)
        #expect(settings.availablePlatesKg == [1.25, 2.5, 5, 10, 15, 20, 25])
        #expect(settings.syncState == .pending)
    }

    @Test func enumRawValuesMatchServerConstraints() {
        #expect(Experience.allCases.map(\.rawValue)
            == ["none", "under_6_months", "six_months_to_2_years", "two_to_5_years", "over_5_years"])
        #expect(Goal.allCases.map(\.rawValue) == ["strength", "muscle_gain", "fat_loss", "general_health"])
        #expect(EquipmentAccess.allCases.map(\.rawValue)
            == ["full_gym", "home_barbell", "home_dumbbell", "bodyweight_only"])
        #expect(ConsentKind.allCases.map(\.rawValue) == ["terms", "privacy", "ai_sharing", "ml_contribution"])
        #expect(MeasurementSource.allCases.map(\.rawValue) == ["manual", "healthkit", "import"])
        #expect(LengthUnit.allCases.map(\.rawValue) == ["cm", "in"])
    }

    @MainActor
    @Test func fixturesSeedAllModels() throws {
        let container = try DataStore.inMemory()
        try DataFixtures.seed(container)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 8)
        #expect(try context.fetchCount(FetchDescriptor<UserSettings>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ConsentRecord>()) == 2)
    }
}
