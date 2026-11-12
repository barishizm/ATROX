import Foundation

/// Weekly set count of one muscle (P033). Secondary muscles count half a set.
public struct MuscleSetCount: Sendable, Equatable, Identifiable {
    public let muscle: String
    public let sets: Double
    public var id: String { muscle }
}

/// Live analysis of a routine for the editor: weekly sets per muscle and empty-day warnings.
public enum RoutineVolume {
    public static let secondaryWeight = 0.5

    /// Muscles of one exercise; `nil` when the exercise is unknown (deleted custom exercise, missing catalog row).
    public typealias MuscleLookup = (ExerciseRef) -> (primary: [String], secondary: [String])?

    /// Every day of a routine is trained once a week, so the weekly volume is the sum over its days. Muscles are
    /// ordered by sets (most first), then by name.
    public static func weeklySets(in routine: RoutineSnapshot, muscles: MuscleLookup) -> [MuscleSetCount] {
        var totals: [String: Double] = [:]
        for exercise in routine.days.flatMap(\.exercises) {
            guard let found = muscles(exercise.ref) else { continue }
            let sets = Double(exercise.input.targetSets)
            for muscle in found.primary { totals[muscle, default: 0] += sets }
            for muscle in found.secondary where !found.primary.contains(muscle) {
                totals[muscle, default: 0] += sets * secondaryWeight
            }
        }
        return totals
            .map { MuscleSetCount(muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle < $1.muscle }
    }

    /// Days without any exercise: they cannot be trained, so the editor warns about them.
    public static func emptyDays(in routine: RoutineSnapshot) -> [RoutineDaySnapshot] {
        routine.days.filter(\.exercises.isEmpty)
    }
}
