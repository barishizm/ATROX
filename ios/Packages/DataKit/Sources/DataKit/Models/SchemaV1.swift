import SwiftData

/// First released local schema. Frozen: later changes add a new `SchemaVn` and a stage in `DataMigrationPlan`.
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
