import Foundation

/// Muscles an exercise works, as catalog names (`"lower_back"`).
public struct ExerciseMuscles: Sendable, Equatable {
    public var primary: [String]
    public var secondary: [String]

    public init(primary: [String], secondary: [String] = []) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Numbers shown on the "workout finished" screen (P041). Pure: built from snapshots, no UI and no storage.
public struct WorkoutSummary: Sendable, Equatable {
    /// How much one set counts for a muscle that is only helping.
    public static let secondaryWeight = 0.5

    public let duration: TimeInterval
    /// Σ weight × reps of the sets that count (completed, not warm-up).
    public let totalVolumeKg: Double
    /// Completed working sets (warm-ups are not counted).
    public let setCount: Int
    public let exerciseCount: Int
    /// Weighted set count per muscle name (primary 1, secondary `secondaryWeight` per set).
    public let muscleLoad: [String: Double]
    /// Records the workout broke: one per exercise and kind, the last hit of each.
    public let records: [PersonalRecordHit]
    public let comparison: Comparison?

    /// This workout against the previous comparable one.
    public struct Comparison: Sendable, Equatable {
        public let previousDate: Date
        public let volumeDeltaKg: Double
        /// `nil` when the previous volume was zero.
        public let volumePercent: Double?
        public let setDelta: Int
        public let durationDelta: TimeInterval
    }

    public init(
        workout: WorkoutSnapshot, previous: WorkoutSnapshot? = nil, muscles: [ExerciseRef: ExerciseMuscles] = [:],
        records: [PersonalRecordHit] = []
    ) {
        let length = max(0, workout.duration ?? 0)
        let counted = Self.workingSets(of: workout)
        let volume = Self.volume(of: workout)
        let sets = counted.reduce(0) { $0 + $1.sets.count }
        duration = length
        totalVolumeKg = volume
        setCount = sets
        exerciseCount = counted.filter { !$0.sets.isEmpty }.count
        muscleLoad = Self.muscleLoad(of: counted, muscles: muscles)
        var latest: [String: PersonalRecordHit] = [:]
        for hit in records where !hit.needsConfirmation { latest["\(hit.ref)|\(hit.kind.rawValue)"] = hit }
        self.records = latest.values.sorted { ($0.kind.rawValue, "\($0.ref)") < ($1.kind.rawValue, "\($1.ref)") }
        comparison = previous.map { previous in
            let before = Self.volume(of: previous)
            return Comparison(
                previousDate: previous.startedAt, volumeDeltaKg: volume - before,
                volumePercent: before > 0 ? (volume - before) / before * 100 : nil,
                setDelta: sets - Self.workingSets(of: previous).reduce(0) { $0 + $1.sets.count },
                durationDelta: length - max(0, previous.duration ?? 0)
            )
        }
    }

    // MARK: Pure helpers

    /// Completed, non-warm-up sets per exercise (an exercise keeps its position even when it has none).
    static func workingSets(of workout: WorkoutSnapshot) -> [(ref: ExerciseRef, sets: [SetSnapshot])] {
        workout.exercises.map { exercise in
            (exercise.ref, exercise.sets.filter { $0.input.isCompleted && $0.input.setType != .warmup })
        }
    }

    public static func volume(of workout: WorkoutSnapshot) -> Double {
        workingSets(of: workout).flatMap(\.sets).reduce(0) { $0 + $1.input.weightKg * Double($1.input.reps) }
    }

    static func muscleLoad(
        of exercises: [(ref: ExerciseRef, sets: [SetSnapshot])], muscles: [ExerciseRef: ExerciseMuscles]
    ) -> [String: Double] {
        var load: [String: Double] = [:]
        for (ref, sets) in exercises where !sets.isEmpty {
            guard let worked = muscles[ref] else { continue }
            for name in worked.secondary where !worked.primary.contains(name) {
                load[name, default: 0] += Double(sets.count) * secondaryWeight
            }
            for name in worked.primary { load[name, default: 0] += Double(sets.count) }
        }
        return load
    }

    /// The finished workout to compare `workout` with: the latest earlier one of the same routine day; failing that
    /// the same name; failing that the one sharing most exercises (at least 60 % of the larger exercise list).
    public static func previousComparable(to workout: WorkoutSnapshot, among others: [WorkoutSnapshot]) -> WorkoutSnapshot? {
        let earlier = others
            .filter { $0.id != workout.id && $0.endedAt != nil && $0.startedAt < workout.startedAt }
            .sorted { $0.startedAt > $1.startedAt }
        if let dayId = workout.routineDayId, let match = earlier.first(where: { $0.routineDayId == dayId }) { return match }
        if let name = workout.name?.lowercased(), !name.isEmpty,
           let match = earlier.first(where: { $0.name?.lowercased() == name }) { return match }
        let refs = Set(workout.exercises.map(\.ref))
        guard !refs.isEmpty else { return nil }
        var best: (WorkoutSnapshot, Double)?
        for candidate in earlier {
            let other = Set(candidate.exercises.map(\.ref))
            let score = Double(refs.intersection(other).count) / Double(max(refs.count, other.count, 1))
            if score >= 0.6, score > (best?.1 ?? 0) { best = (candidate, score) }
        }
        return best?.0
    }
}

/// What to ask before a workout is saved (P041): open sets, and whether it is worth keeping at all.
public struct FinishAssessment: Sendable, Equatable {
    /// Workouts shorter than this ask before saving.
    public static let shortWorkout: TimeInterval = 120

    public let completedSets: Int
    public let incompleteSets: Int
    public let elapsed: TimeInterval

    public init(workout: WorkoutSnapshot, now: Date) {
        let sets = workout.exercises.flatMap(\.sets)
        completedSets = sets.filter(\.input.isCompleted).count
        incompleteSets = sets.count - completedSets
        elapsed = max(0, now.timeIntervalSince(workout.startedAt))
    }

    /// Nothing was completed: finishing can only throw the workout away.
    public var isEmpty: Bool { completedSets == 0 }
    public var isShort: Bool { elapsed < Self.shortWorkout }
    /// Ask "save this?" first: empty or shorter than two minutes.
    public var needsSaveConfirmation: Bool { isEmpty || isShort }
    public var hasOpenSets: Bool { incompleteSets > 0 }
}
