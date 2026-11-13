import Foundation
import StrengthKit

/// Why an exercise's score is less certain (shown under the confidence badge).
public enum ConfidenceReason: String, Sendable, Equatable, CaseIterable {
    /// Fewer than three sessions inside the strength window.
    case fewSessions
    /// The deciding set had 12 or more reps: the e1RM extrapolates far.
    case highReps
    case machine
    /// No session inside the window: the value is a decayed best.
    case stale
    /// The exercise is scored through a ratio to a powerlifting lift, which is an estimate.
    case estimatedRatio
}

public enum NotScorable: Sendable, Equatable {
    /// Custom exercise, time-based or not part of the score model.
    case notInModel
    /// Scorable, but nothing usable has been logged.
    case noData
    /// The set history is there but yields no e1RM (e.g. only very high-rep sets).
    case noStrength
}

/// A load that reaches the next level with a given number of reps.
public struct TargetLoad: Sendable, Equatable {
    public var reps: Int
    /// In the exercise's logged convention (added load for bodyweight moves), not rounded.
    public var weightKg: Double
}

/// All numbers of the exercise score screen for one reference group.
public struct ExerciseInsight: Sendable, Equatable {
    public var population: ReferencePopulation
    public var exerciseId: String
    public var notScorable: NotScorable?
    public var evaluation: ExerciseEvaluation?
    public var distribution: ScoreDistribution?
    public var nextTarget: ScoreTarget?
    public var targetLoads: [TargetLoad]
    /// e1RM range that the uncertainty band spans (shaded on the chart).
    public var bandE1RMKg: ClosedRange<Double>?
    public var reasons: [ConfidenceReason]
    public var userAge: Int
    public var userBodyweightKg: Double
}

extension ScoreService {
    /// Rep counts offered for the next-level target.
    public static let targetReps = [3, 5, 8]

    /// Score, distribution chart data, next-level target and confidence reasons of one exercise under `population`.
    public func insight(userId: UUID, exerciseId: String, population: ReferencePopulation) async -> ExerciseInsight? {
        guard let scoring = await currentScoringModel(), case .success(let user) = currentUser(userId: userId) else { return nil }
        let id = ScoreCalculator.scoringId(exerciseId)
        var insight = ExerciseInsight(
            population: population, exerciseId: id, notScorable: nil, evaluation: nil, distribution: nil, nextTarget: nil,
            targetLoads: [], bandE1RMKg: nil, reasons: [], userAge: Int(user.age), userBodyweightKg: user.bodyweightKg
        )
        guard let ex = scoring.model.exercises[id], ex.scorable || ex.scoringType == "reps_only" else {
            insight.notScorable = .notInModel
            return insight
        }
        let sets = (try? loadScoredSets(userId: userId, exerciseIds: [id])) ?? [:]
        guard let history = sets[id], !history.isEmpty else {
            insight.notScorable = .noData
            return insight
        }
        let today = ScoreCalculator.dayNumber(currentDate(), calendar: currentCalendar)
        guard let evaluation = ScoreCalculator.evaluate(
            id, sets: history, model: scoring.model, user: user, population: population, asOfDay: today
        ) else {
            insight.notScorable = .noStrength
            return insight
        }
        insight.evaluation = evaluation
        insight.reasons = Self.reasons(for: evaluation, exercise: ex)
        guard let e1rm = evaluation.strength.e1rmKg, ex.scoringType != "reps_only" else { return insight }
        let model = scoring.model
        insight.distribution = try? model.scoreDistribution(exerciseId: id, user: user, population: population)
        if let target = try? model.nextLevelTarget(
            exerciseId: id, currentScore: evaluation.score.score, currentE1RMKg: e1rm, user: user, population: population
        ) {
            insight.nextTarget = target
            insight.targetLoads = Self.targetReps.compactMap { reps in
                (try? model.loadForReps(exerciseId: id, e1rmKg: target.e1rmKg, reps: reps, user: user))
                    .map { TargetLoad(reps: reps, weightKg: $0) }
            }
        }
        if let low = try? model.e1rmForScore(exerciseId: id, targetScore: evaluation.score.bandLow, user: user, population: population),
           let high = try? model.e1rmForScore(exerciseId: id, targetScore: evaluation.score.bandHigh, user: user, population: population),
           low <= high {
            insight.bandE1RMKg = low...high
        }
        return insight
    }

    static func reasons(for evaluation: ExerciseEvaluation, exercise ex: TaxonomyExercise) -> [ConfidenceReason] {
        var out: [ConfidenceReason] = []
        if evaluation.strength.sessionsInWindow < 3 { out.append(.fewSessions) }
        if let reps = evaluation.basis?.reps, reps >= 12 { out.append(.highReps) }
        if evaluation.score.isMachine { out.append(.machine) }
        if evaluation.strength.stale { out.append(.stale) }
        if !ex.isAnchor, let grade = ex.ratioConfidence, grade != "A" { out.append(.estimatedRatio) }
        return out
    }
}
