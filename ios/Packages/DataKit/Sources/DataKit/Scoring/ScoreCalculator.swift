import Foundation
import StrengthKit

/// The scoring model of the moment and its version (from `ModelUpdater`, or the embedded base bundle).
public struct ScoringModel: Sendable {
    public let model: StrengthModel
    public let version: String

    public init(model: StrengthModel, version: String) {
        self.model = model
        self.version = version
    }
}

/// One logged set as the score engine needs it, plus the id that lets the UI point at the deciding set.
public struct ScoredSet: Sendable, Equatable {
    public var setId: UUID?
    public var set: ScoringSet

    public init(setId: UUID? = nil, set: ScoringSet) {
        self.setId = setId
        self.set = set
    }
}

/// The set that decides an exercise's strength ("Dayanak").
public struct ScoreBasis: Sendable, Equatable {
    public var setId: UUID?
    public var day: Int
    public var weightKg: Double
    public var reps: Int
    public var e1rmKg: Double
}

public struct ExerciseEvaluation: Sendable, Equatable {
    public var score: ExerciseScore
    public var strength: CurrentStrength
    public var basis: ScoreBasis?
    /// Best reps of the last 90 days; what `reps_only` exercises are scored on.
    public var bestReps: Double?
}

/// Everything the score screens show, for one reference group and one day.
public struct ScoreOverview: Sendable, Equatable {
    public var population: ReferencePopulation
    public var modelVersion: String
    public var asOfDay: Int
    public var exercises: [String: ExerciseEvaluation]
    public var muscles: [String: GroupScore]
    public var overall: GroupScore?
}

/// Pure score computation: sets in, scores out. The service wraps it with storage, caching and snapshots.
public enum ScoreCalculator {
    /// Catalog ids the onboarding history uses → the scored exercise they stand for (P062 note).
    public static let aliases: [String: String] = ["barbell-squat": "barbell-full-squat"]

    public static func scoringId(_ id: String) -> String { aliases[id] ?? id }

    /// Ids whose sets feed the scored exercise `id` (itself and its aliases).
    public static func sourceIds(of id: String) -> [String] {
        [id] + aliases.filter { $0.value == id }.map(\.key)
    }

    public static func evaluate(
        _ exerciseId: String, sets: [ScoredSet], model: StrengthModel, user: ScoringUser, population: ReferencePopulation, asOfDay: Int
    ) -> ExerciseEvaluation? {
        guard let ex = try? model.exercise(exerciseId), !sets.isEmpty else { return nil }
        let usable = sets.filter { $0.set.day <= asOfDay }
        guard !usable.isEmpty,
              let strength = try? model.currentStrength(ex, sets: usable.map(\.set), user: user, asOfDay: asOfDay) else { return nil }
        let recent = usable.map(\.set).filter { !$0.isWarmup && asOfDay - $0.day <= 90 }
        let bestReps = recent.map { Double($0.reps) }.max()
        guard let score = try? model.exerciseScore(ex, strength: strength, user: user, population: population, reps: bestReps)
        else { return nil }
        return ExerciseEvaluation(score: score, strength: strength, basis: basis(ex, usable, strength: strength, model: model, user: user), bestReps: bestReps)
    }

    /// The set whose e1RM is closest to the current strength (exact unless the value is a stale decayed one).
    private static func basis(
        _ ex: TaxonomyExercise, _ sets: [ScoredSet], strength: CurrentStrength, model: StrengthModel, user: ScoringUser
    ) -> ScoreBasis? {
        guard let target = strength.e1rmKg else { return nil }
        var best: (distance: Double, basis: ScoreBasis)?
        for item in sets {
            guard let est = try? model.scoreSet(ex, item.set, user: user), est.confidence >= model.params.currentStrength.minSetConfidence
            else { continue }
            let distance = abs(est.valueKg - target)
            let candidate = ScoreBasis(
                setId: item.setId, day: item.set.day, weightKg: item.set.weightKg, reps: item.set.reps, e1rmKg: est.valueKg
            )
            if best == nil || distance < best!.distance - 1e-9 || (abs(distance - best!.distance) <= 1e-9 && candidate.day > best!.basis.day) {
                best = (distance, candidate)
            }
        }
        return best?.basis
    }

    /// Aggregates exercise evaluations into muscle and overall scores. Exercise order does not matter.
    public static func overview(
        evaluations: [String: ExerciseEvaluation], model: StrengthModel, version: String, population: ReferencePopulation, asOfDay: Int
    ) -> ScoreOverview {
        let ordered = evaluations.keys.sorted().compactMap { evaluations[$0]?.score }
        let muscles = (try? model.muscleGroupScores(ordered)) ?? [:]
        let overall = (try? model.overallScore(ordered)) ?? nil
        return ScoreOverview(
            population: population, modelVersion: version, asOfDay: asOfDay, exercises: evaluations, muscles: muscles, overall: overall
        )
    }

    public static func compute(
        sets: [String: [ScoredSet]], scoring: ScoringModel, user: ScoringUser, population: ReferencePopulation, asOfDay: Int
    ) -> ScoreOverview {
        var evaluations: [String: ExerciseEvaluation] = [:]
        for (id, exerciseSets) in sets {
            if let value = evaluate(id, sets: exerciseSets, model: scoring.model, user: user, population: population, asOfDay: asOfDay) {
                evaluations[id] = value
            }
        }
        return overview(evaluations: evaluations, model: scoring.model, version: scoring.version, population: population, asOfDay: asOfDay)
    }

    /// Day number of a date in the calendar's time zone (same origin everywhere; only differences matter).
    public static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        Int(((date.timeIntervalSince1970 + Double(calendar.timeZone.secondsFromGMT(for: date))) / 86_400).rounded(.down))
    }

    /// Noon of a day number in the calendar's zone: stable under daylight saving shifts and `SyncTime.day`.
    public static func date(ofDay day: Int, calendar: Calendar = .current) -> Date {
        let utc = Date(timeIntervalSince1970: Double(day) * 86_400)
        let offset = Double(calendar.timeZone.secondsFromGMT(for: utc))
        return Date(timeIntervalSince1970: Double(day) * 86_400 - offset + 43_200)
    }

    public static func age(birthDate: Date, on date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }
}

/// Bodyweight used for scoring and whether it is old enough to ask for an update (P064: 60 days).
public struct BodyweightStatus: Sendable, Equatable {
    public static let staleAfterDays = 60

    public var weightKg: Double
    public var measuredAt: Date
    public var isStale: Bool

    public init(weightKg: Double, measuredAt: Date, now: Date, calendar: Calendar = .current) {
        self.weightKg = weightKg
        self.measuredAt = measuredAt
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: measuredAt), to: calendar.startOfDay(for: now)).day ?? 0
        isStale = days > Self.staleAfterDays
    }
}
