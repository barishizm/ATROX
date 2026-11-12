import SwiftData

/// P028: adds the exercise catalog (`Exercise`) and its bookkeeping row (`CatalogInfo`). The V1 models are unchanged,
/// so the V1 → V2 migration is lightweight (two new entities).
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV1.models + [Exercise.self, CatalogInfo.self]
    }
}

public typealias Exercise = SchemaV2.Exercise
public typealias CatalogInfo = SchemaV2.CatalogInfo

public enum DataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self] }
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
        ]
    }
}
