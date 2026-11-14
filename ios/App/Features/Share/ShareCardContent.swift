import DataKit
import Foundation
import StrengthKit

/// What a share card shows (P084). Pure data: formatted values only, so every template renders the same way in tests,
/// previews and the share sheet. Localised labels live in the card view (it renders under the user's locale).
struct ShareCardContent: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Overall Strength Score.
        case overall
        /// One exercise's score.
        case exercise
        /// A new personal record.
        case record
        /// The weekly summary.
        case weekly
    }

    struct Stat: Equatable, Sendable, Identifiable {
        /// A `Localizable.xcstrings` key for fixed labels, or a ready text when `isVerbatim`.
        let label: String
        let value: String
        var isVerbatim = false
        var id: String { label }
    }

    var kind: Kind
    /// Exercise or period name under the big number ("Bench Press", "11–17 Nov").
    var title: String
    /// 0…100, drawn as the ring; nil for cards without a score (records).
    var score: Int?
    /// Big text when there is no ring ("120 kg").
    var headline: String?
    /// Level name ("Advanced") under the score.
    var level: String?
    var stats: [Stat] = []
    /// "Gym-goers · men · 80 kg class" — which group the score is measured against.
    var referenceLabel: String?
    var displayName: String?
    /// Shown only when the user turns it on (off by default).
    var bodyweightText: String?
}

/// What the user chose to put on the card.
struct ShareCardOptions: Equatable, Sendable {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case story, square
        var id: String { rawValue }
        /// Pixel size of the exported image (1× render).
        var size: CGSize { self == .story ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1080) }
    }

    var format: Format = .story
    var showsName = true
    /// Default off: body weight is private unless the user opts in.
    var showsBodyweight = false
    var showsReference = true
}

extension ShareCardContent {
    static func overall(
        score: Double, level: String, reference: String?, name: String?, bodyweight: String?, stats: [Stat] = []
    ) -> ShareCardContent {
        ShareCardContent(
            kind: .overall, title: "", score: clamp(score), level: level, stats: stats, referenceLabel: reference,
            displayName: name, bodyweightText: bodyweight
        )
    }

    static func exercise(
        name: String, score: Double, level: String, reference: String?, e1rm: String?, person: String?, bodyweight: String?
    ) -> ShareCardContent {
        ShareCardContent(
            kind: .exercise, title: name, score: clamp(score), level: level,
            stats: e1rm.map { [Stat(label: "share.stat.e1rm", value: $0)] } ?? [], referenceLabel: reference, displayName: person,
            bodyweightText: bodyweight
        )
    }

    static func record(exercise: String, kindLabel: String, value: String, name: String?) -> ShareCardContent {
        ShareCardContent(
            kind: .record, title: exercise, headline: value,
            stats: [Stat(label: kindLabel, value: "", isVerbatim: true)], displayName: name
        )
    }

    static func weekly(
        period: String, workouts: Int, goal: Int, sets: Int, records: Int, score: Double?, level: String?, name: String?
    ) -> ShareCardContent {
        var stats = [
            Stat(label: "share.stat.workouts", value: goal > 0 ? "\(workouts)/\(goal)" : "\(workouts)"),
            Stat(label: "share.stat.sets", value: "\(sets)")
        ]
        if records > 0 { stats.append(Stat(label: "share.stat.records", value: "\(records)")) }
        return ShareCardContent(
            kind: .weekly, title: period, score: score.map(clamp), level: level, stats: stats, displayName: name
        )
    }

    private static func clamp(_ score: Double) -> Int { min(max(Int(score.rounded()), 1), 99) }
}
