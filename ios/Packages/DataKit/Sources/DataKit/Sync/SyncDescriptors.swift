import Foundation
import SwiftData

// Concrete fetch descriptors for the sync engine. SwiftData predicates need concrete key paths, so they cannot be
// written once over the generic `SyncableModel`; this file repeats the same four filters per model.

extension UserProfile {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<UserProfile> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<UserProfile> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<UserProfile> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<UserProfile> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension UserSettings {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<UserSettings> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<UserSettings> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<UserSettings> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<UserSettings> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension BodyMeasurement {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<BodyMeasurement> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<BodyMeasurement> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<BodyMeasurement> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<BodyMeasurement> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension CustomExercise {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<CustomExercise> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<CustomExercise> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<CustomExercise> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<CustomExercise> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension Routine {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<Routine> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<Routine> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<Routine> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<Routine> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension RoutineDay {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<RoutineDay> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<RoutineDay> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<RoutineDay> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<RoutineDay> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension RoutineExercise {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<RoutineExercise> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<RoutineExercise> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<RoutineExercise> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<RoutineExercise> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension Workout {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<Workout> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<Workout> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<Workout> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<Workout> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension WorkoutExercise {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<WorkoutExercise> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<WorkoutExercise> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<WorkoutExercise> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<WorkoutExercise> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension SetEntry {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<SetEntry> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<SetEntry> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<SetEntry> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<SetEntry> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension PersonalRecord {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<PersonalRecord> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<PersonalRecord> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<PersonalRecord> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<PersonalRecord> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension ScoreSnapshot {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<ScoreSnapshot> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<ScoreSnapshot> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<ScoreSnapshot> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<ScoreSnapshot> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}

extension InsightRecord {
    public static func syncDescriptor(_ filter: SyncFilter) -> FetchDescriptor<InsightRecord> {
        switch filter {
        case .state(let state, let userId):
            let raw = state.rawValue
            return FetchDescriptor(predicate: #Predicate<InsightRecord> { $0.userId == userId && $0.syncStateRaw == raw })
        case .id(let id):
            var descriptor = FetchDescriptor(predicate: #Predicate<InsightRecord> { $0.id == id })
            descriptor.fetchLimit = 1
            return descriptor
        case .user(let userId):
            return FetchDescriptor(predicate: #Predicate<InsightRecord> { $0.userId == userId })
        case .all:
            return FetchDescriptor()
        }
    }
}
