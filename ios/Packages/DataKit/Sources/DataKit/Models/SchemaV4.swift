import SwiftData

/// P032: adds routines and workouts (`Routine`, `RoutineDay`, `RoutineExercise`, `Workout`, `WorkoutExercise`,
/// `SetEntry`, `PersonalRecord`). Existing models are unchanged, so the V3 → V4 migration is lightweight (seven new
/// entities). docs/02-MIMARI.md §2.3 asked for these in V1, but V1 is already frozen and released to testers.
public enum SchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV3.models + [
            Routine.self, RoutineDay.self, RoutineExercise.self,
            Workout.self, WorkoutExercise.self, SetEntry.self, PersonalRecord.self,
        ]
    }
}

public typealias Routine = SchemaV4.Routine
public typealias RoutineDay = SchemaV4.RoutineDay
public typealias RoutineExercise = SchemaV4.RoutineExercise
public typealias Workout = SchemaV4.Workout
public typealias WorkoutExercise = SchemaV4.WorkoutExercise
public typealias SetEntry = SchemaV4.SetEntry
public typealias PersonalRecord = SchemaV4.PersonalRecord
