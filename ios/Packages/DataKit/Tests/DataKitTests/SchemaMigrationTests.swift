@testable import DataKit
import Foundation
import SwiftData
import Testing

/// Pattern for every schema change after the first release (P099): write a store with an old schema, open it with the
/// current `DataStore`, check the user's rows survived. Add the new version to `versions` with each `SchemaVn`.
struct MigrationVersion: Sendable, CustomTestStringConvertible {
    let name: String
    let schema: any VersionedSchema.Type
    let plan: any SchemaMigrationPlan.Type
    var testDescription: String { name }
}

@Suite("Schema migration from every historical version (P099)")
struct SchemaMigrationTests {
    private enum Only1: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }
    private enum Only2: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV2.self] }
        static var stages: [MigrationStage] { [] }
    }
    private enum Only3: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV3.self] }
        static var stages: [MigrationStage] { [] }
    }
    private enum Only4: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV4.self] }
        static var stages: [MigrationStage] { [] }
    }
    private enum Only5: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV5.self] }
        static var stages: [MigrationStage] { [] }
    }
    private enum Only6: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV6.self] }
        static var stages: [MigrationStage] { [] }
    }

    private enum Only7: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV7.self] }
        static var stages: [MigrationStage] { [] }
    }

    private enum Only8: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV8.self] }
        static var stages: [MigrationStage] { [] }
    }

    private enum Only9: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [SchemaV9.self] }
        static var stages: [MigrationStage] { [] }
    }

    private static let versions: [MigrationVersion] = [
        MigrationVersion(name: "V1", schema: SchemaV1.self, plan: Only1.self),
        MigrationVersion(name: "V2", schema: SchemaV2.self, plan: Only2.self),
        MigrationVersion(name: "V3", schema: SchemaV3.self, plan: Only3.self),
        MigrationVersion(name: "V4", schema: SchemaV4.self, plan: Only4.self),
        MigrationVersion(name: "V5", schema: SchemaV5.self, plan: Only5.self),
        MigrationVersion(name: "V6", schema: SchemaV6.self, plan: Only6.self),
        MigrationVersion(name: "V7", schema: SchemaV7.self, plan: Only7.self),
        MigrationVersion(name: "V8", schema: SchemaV8.self, plan: Only8.self),
        MigrationVersion(name: "V9", schema: SchemaV9.self, plan: Only9.self),
    ]

    @Test func everyHistoricalVersionIsCoveredByThePlan() {
        #expect(DataMigrationPlan.schemas.count == Self.versions.count + 1)
    }

    @Test(arguments: SchemaMigrationTests.versions)
    func oldStoreOpensWithTheCurrentSchemaAndKeepsUserData(version: MigrationVersion) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let rowId: UUID
        do {
            let schema = Schema(versionedSchema: version.schema)
            let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("ATROX.store"))
            let old = try ModelContainer(for: schema, migrationPlan: version.plan, configurations: config)
            let context = ModelContext(old)
            let row = BodyMeasurement(userId: testUser, input: MeasurementInput(date: Date(timeIntervalSince1970: 1_700_000_000), weightKg: 82.5),
                now: Date(timeIntervalSince1970: 1_700_000_000))
            rowId = row.id
            context.insert(row)
            try context.save()
        }

        let current = try DataStore.onDisk(directory: dir)
        let rows = try ModelContext(current).fetch(FetchDescriptor<BodyMeasurement>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == rowId)
        #expect(rows.first?.weightKg == 82.5)
    }
}
