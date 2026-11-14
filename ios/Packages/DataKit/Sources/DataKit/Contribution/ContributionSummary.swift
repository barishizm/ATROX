import Foundation
import StrengthKit

/// Builds the monthly summary: pure, so banding and the "only trustworthy core lifts" rule are testable.
public enum ContributionSummary {
    public static let maxLifts = 40

    /// The finished month before `now`, as day numbers (inclusive) and its `YYYY-MM` label.
    public static func previousMonth(now: Date, calendar: Calendar) -> (label: String, firstDay: Int, lastDay: Int)? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let previous = calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1)) else { return nil }
        let first = ScoreCalculator.dayNumber(previous.start, calendar: calendar)
        let last = ScoreCalculator.dayNumber(thisMonth.start, calendar: calendar) - 1
        return (ContributionBanding.monthString(previous.start, calendar: calendar), first, last)
    }

    /// nil when there is nothing worth sending: unspecified sex, an implausible body, or no qualifying lift.
    /// A lift qualifies when the model scores it (a core exercise) and at least one working set of the month has an
    /// e1RM estimate at or above the model's own minimum confidence ("medium" or better).
    public static func build(
        key: UUID, inputs: ContributionInputs, sets: [String: [ScoredSet]], model: ScoringModel, month: (label: String, firstDay: Int, lastDay: Int),
        calendar: Calendar
    ) -> ContributionPayload? {
        let sex: String
        let modelSex: ModelSex
        switch inputs.sex {
        case .male: (sex, modelSex) = ("male", .male)
        case .female: (sex, modelSex) = ("female", .female)
        case .unspecified: return nil
        }
        let monthEnd = ScoreCalculator.date(ofDay: month.lastDay, calendar: calendar)
        let age = ScoreCalculator.age(birthDate: inputs.birthDate, on: monthEnd, calendar: calendar)
        guard age >= 13, inputs.bodyweightKg >= 30, inputs.bodyweightKg <= 300, inputs.heightCm >= 120 else { return nil }
        let user = ScoringUser(sex: modelSex, age: Double(age), bodyweightKg: inputs.bodyweightKg)
        let minConfidence = model.model.params.currentStrength.minSetConfidence

        var lifts: [ContributionPayload.Lift] = []
        for id in sets.keys.sorted() {
            guard let exercise = try? model.model.exercise(id) else { continue }
            let working = (sets[id] ?? []).map(\.set).filter { !$0.isWarmup && $0.day >= month.firstDay && $0.day <= month.lastDay && $0.reps <= 30 }
            var best: (valueKg: Double, reps: Int)?
            for set in working {
                guard let estimate = try? model.model.scoreSet(exercise, set, user: user), estimate.confidence >= minConfidence,
                      estimate.valueKg > 0, estimate.valueKg <= 700 else { continue }
                if best == nil || estimate.valueKg > best!.valueKg { best = (estimate.valueKg, set.reps) }
            }
            guard let best else { continue }
            let sessions = Set(working.map(\.day)).count
            lifts.append(
                ContributionPayload.Lift(
                    exerciseId: id, bestE1rmKg: (best.valueKg * 10).rounded() / 10, bestSetReps: best.reps, sessionsInMonth: min(62, max(1, sessions))
                )
            )
        }
        guard !lifts.isEmpty else { return nil }
        return ContributionPayload(
            contributionKey: key, sex: sex, ageBand: ContributionBanding.ageBand(age), bodyweightKg: ContributionBanding.bodyweight(inputs.bodyweightKg),
            heightBand: ContributionBanding.heightBand(inputs.heightCm), experienceBand: inputs.experience.rawValue,
            frequencyBand: ContributionBanding.frequencyBand(inputs.weeklyFrequency), month: month.label, modelVersion: model.version,
            lifts: Array(lifts.prefix(maxLifts))
        )
    }
}
