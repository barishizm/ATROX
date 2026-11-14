import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// Builds card content from each entry point's data and wires the share button into it (P084).
enum ShareLocalized {
    static func string(_ key: String, locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(key), locale: locale))
    }

    static func reference(_ population: ReferencePopulation, locale: Locale) -> String {
        switch population {
        case .gym: string("share.reference.gym", locale: locale)
        case .general: string("share.reference.general", locale: locale)
        case .competitor: string("share.reference.competitor", locale: locale)
        }
    }
}

extension ExerciseScoreModel {
    /// The single-exercise card; nil until a score exists.
    var shareContent: ShareCardContent? {
        guard let score, let levelName else { return nil }
        let e1rm = insight?.evaluation?.strength.e1rmKg.map(weightText)
        let bodyweight = insight.map { weightText($0.userBodyweightKg) }
        return .exercise(
            name: name, score: score, level: levelName, reference: ShareLocalized.reference(population, locale: locale),
            e1rm: e1rm, person: nil, bodyweight: bodyweight
        )
    }
}

/// Overall Strength Score card from the Today dashboard.
struct OverallShareButton: View {
    let score: Double
    let population: ReferencePopulation
    @Environment(\.locale) private var locale

    var body: some View {
        ShareCardButton(content: .overall(
            score: score, level: ScoreLevel(score: score).localizedName(locale: locale),
            reference: ShareLocalized.reference(population, locale: locale), name: nil, bodyweight: nil
        ))
        .labelStyle(.iconOnly)
    }
}

/// "New record" card from the workout summary.
struct RecordShareButton: View {
    let exercise: String
    let kind: RecordKind
    let value: String
    @Environment(\.locale) private var locale

    var body: some View {
        let label = ShareLocalized.string(Self.key(kind), locale: locale)
        ShareCardButton(content: .record(exercise: exercise, kindLabel: label, value: value, name: nil))
            .labelStyle(.iconOnly)
    }

    static func key(_ kind: RecordKind) -> String {
        switch kind {
        case .weight: "workout.record.weight"
        case .reps: "workout.record.reps"
        case .e1rm: "workout.record.e1rm"
        case .volume: "workout.record.volume"
        }
    }
}

/// Weekly summary card.
struct WeeklyShareButton: View {
    let week: WeeklySummaryModel.Week
    @Environment(\.locale) private var locale

    var body: some View {
        let summary = week.summary
        ShareCardButton(content: .weekly(
            period: week.title, workouts: summary.workouts, goal: summary.goal, sets: summary.totalSets,
            records: summary.records.count, score: summary.overallScore,
            level: summary.overallScore.map { ScoreLevel(score: $0).localizedName(locale: locale) }, name: nil
        ))
        .labelStyle(.iconOnly)
    }
}
