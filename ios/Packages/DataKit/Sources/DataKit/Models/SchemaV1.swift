import SwiftData

/// First released local schema. Later model changes add `SchemaV2` and a stage in `DataMigrationPlan`.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [UserProfile.self, BodyMeasurement.self, UserSettings.self, ConsentRecord.self]
    }
}

public typealias UserProfile = SchemaV1.UserProfile
public typealias BodyMeasurement = SchemaV1.BodyMeasurement
public typealias UserSettings = SchemaV1.UserSettings
public typealias ConsentRecord = SchemaV1.ConsentRecord

public enum DataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
