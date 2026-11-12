import Foundation

/// Pre-fills the planned sets of an exercise when a workout starts or an exercise is added (P035).
/// Pure, so the rules are tested without a store.
public enum WorkoutPrefill {
    /// Set count when there is neither a routine target nor any history.
    public static let defaultSetCount = 3

    /// - Parameters:
    ///   - target: the routine row's targets, when the exercise comes from a routine day.
    ///   - last: the completed sets of the exercise's most recent finished session, in order.
    /// - Returns: uncompleted sets. With a target the count is `targetSets` and every set is a working set whose
    ///   weight and reps come from last time's working sets by index (else the last one; reps fall back to the top of
    ///   the target range); RIR is the target RIR. Without a target last time is repeated as it was (warm-ups
    ///   included), or `defaultSetCount` empty working sets are planned.
    public static func sets(target: RoutineExerciseInput?, last: [SetInput]) -> [SetInput] {
        guard let target else {
            guard !last.isEmpty else { return Array(repeating: SetInput(), count: defaultSetCount) }
            return last.map { SetInput(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, setType: $0.setType) }
        }
        let working = last.filter { $0.setType != .warmup }
        let targetReps = target.targetRepsMax ?? target.targetRepsMin ?? 0
        return (0..<target.targetSets).map { index in
            let base = index < working.count ? working[index] : working.last
            return SetInput(
                weightKg: base?.weightKg ?? 0, reps: base?.reps ?? targetReps, rir: target.targetRir,
                setType: .working
            )
        }
    }

    /// The set appended by "add set": a copy of the exercise's last set, not completed.
    public static func nextSet(after existing: [SetInput]) -> SetInput {
        guard let last = existing.last else { return SetInput() }
        return SetInput(weightKg: last.weightKg, reps: last.reps, rir: last.rir, setType: last.setType == .warmup ? .working : last.setType)
    }
}
