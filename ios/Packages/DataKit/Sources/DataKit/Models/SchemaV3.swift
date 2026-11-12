import SwiftData

/// P031: adds the user's own exercises (`CustomExercise`). Existing models are unchanged, so the V2 → V3 migration
/// is lightweight (one new entity).
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV2.models + [CustomExercise.self]
    }
}

public typealias CustomExercise = SchemaV3.CustomExercise
