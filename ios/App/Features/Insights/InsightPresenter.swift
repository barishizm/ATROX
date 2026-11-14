import DataKit
import DesignSystem
import Foundation

/// An insight with its localized text, ready for a card.
struct InsightItem: Identifiable, Equatable {
    let insight: Insight
    let title: String
    let body: String
    let actionTitle: String
    let icon: String
    /// Ready-made message for the coach ("Ask the coach").
    let coachPrompt: String

    var id: UUID { insight.id }
}

/// Looks a String Catalog key up for an explicit locale (the in-app language override does not change the process
/// language) and fills in its arguments.
enum LocalizedText {
    static func string(_ key: String, locale: Locale, _ args: CVarArg...) -> String {
        let format = bundle(for: locale).localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, locale: locale, arguments: args)
    }

    static func bundle(for locale: Locale) -> Bundle {
        guard let code = locale.language.languageCode?.identifier, let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// Turns the text-free `Insight` into localized, non-judging, single-action copy (P069).
enum InsightPresenter {
    static func item(for insight: Insight, names: [String: String], locale: Locale) -> InsightItem {
        let (title, body) = text(for: insight, names: names, locale: locale)
        return InsightItem(
            insight: insight, title: title, body: body,
            actionTitle: LocalizedText.string("insight.action.\(insight.action.rawValue)", locale: locale), icon: icon(insight.kind),
            coachPrompt: LocalizedText.string("insight.coach.prompt %@", locale: locale, title)
        )
    }

    // MARK: Text

    private static func text(for insight: Insight, names: [String: String], locale: Locale) -> (String, String) {
        let kind = insight.kind.rawValue
        let payload = insight.payload
        let subject = payload.subjects.first.map { name($0, names: names, locale: locale) } ?? ""
        switch insight.kind {
        case .plateau:
            return (
                LocalizedText.string("insight.plateau.title %@", locale: locale, subject),
                LocalizedText.string("insight.plateau.body %lld", locale: locale, Int(payload.values["sessions"] ?? 0))
            )
        case .progressFast, .progressSlow:
            let observed = percent(payload.values["observed_pct"], locale: locale), expected = percent(payload.values["expected_pct"], locale: locale)
            return (
                LocalizedText.string("insight.\(kind).title %@", locale: locale, subject),
                LocalizedText.string("insight.\(kind).body %@ %@", locale: locale, observed, expected)
            )
        case .neglectedMuscle:
            let muscle = muscleName(insight.subject, locale: locale)
            return (
                LocalizedText.string("insight.neglected_muscle.title %@", locale: locale, muscle),
                LocalizedText.string("insight.neglected_muscle.body %@", locale: locale, number(payload.values["weekly_average"], locale: locale))
            )
        case .pushPull:
            let variant = payload.variant == "push_behind" ? "push_behind" : "pull_behind"
            return (
                LocalizedText.string("insight.push_pull.title.\(variant)", locale: locale),
                LocalizedText.string(
                    "insight.push_pull.body %@ %@", locale: locale, number(payload.values["push_sets"], locale: locale),
                    number(payload.values["pull_sets"], locale: locale)
                )
            )
        case .comeback:
            return (
                LocalizedText.string("insight.comeback.title", locale: locale),
                LocalizedText.string("insight.comeback.body %lld", locale: locale, Int(payload.values["days"] ?? 0))
            )
        case .bodyweightStale:
            return (
                LocalizedText.string("insight.bodyweight_stale.title", locale: locale),
                LocalizedText.string("insight.bodyweight_stale.body %lld", locale: locale, Int(payload.values["days"] ?? 0))
            )
        case .repRangeStuck:
            let variant = ["strength", "hypertrophy", "endurance"].contains(payload.variant) ? payload.variant : "hypertrophy"
            return (
                LocalizedText.string("insight.rep_range_stuck.title", locale: locale),
                LocalizedText.string("insight.rep_range_stuck.body.\(variant) %@", locale: locale, percent(payload.values["share"].map { $0 * 100 }, locale: locale, signed: false))
            )
        case .imbalance:
            return imbalance(insight, subject: subject, locale: locale)
        }
    }

    private static let ratioGroups: [String: (String, String)] = [
        "push_pull": ("push", "pull"), "upper_lower": ("upper", "lower"), "squat_deadlift": ("squat", "hinge"),
    ]

    /// `ratio_rule.<rule>.<weak>_behind`, `conditional_residual.<lift>.<below|above>_expected`, `left_right.<side>_behind`.
    private static func imbalance(_ insight: Insight, subject: String, locale: Locale) -> (String, String) {
        let parts = insight.payload.variant.split(separator: ".").map(String.init)
        guard let first = parts.first else { return generic(locale) }
        switch first {
        case "ratio_rule":
            guard parts.count == 3, let pair = ratioGroups[parts[1]] else { return generic(locale) }
            let weak = parts[2].replacingOccurrences(of: "_behind", with: "")
            let strong = weak == pair.0 ? pair.1 : pair.0
            let weakName = LocalizedText.string("insight.group.\(weak)", locale: locale)
            let strongName = LocalizedText.string("insight.group.\(strong)", locale: locale)
            return (
                LocalizedText.string("insight.imbalance.ratio.title %@ %@", locale: locale, weakName, strongName),
                LocalizedText.string("insight.imbalance.ratio.body %@ %@", locale: locale, weakName, strongName)
            )
        case "conditional_residual":
            guard parts.count == 3 else { return generic(locale) }
            let lift = LocalizedText.string("insight.lift.\(parts[1])", locale: locale)
            let side = parts[2] == "below_expected" ? "below" : "above"
            return (
                LocalizedText.string("insight.imbalance.residual.\(side).title %@", locale: locale, lift),
                LocalizedText.string("insight.imbalance.residual.\(side).body %@", locale: locale, lift)
            )
        case "left_right":
            let weak = parts.count == 2 && parts[1].hasPrefix("left") ? "left" : "right"
            let percentText = percent(insight.payload.values["magnitude"].map { $0 * 100 }, locale: locale, signed: false)
            return (
                LocalizedText.string("insight.imbalance.side.title.\(weak) %@", locale: locale, subject),
                LocalizedText.string("insight.imbalance.side.body %@", locale: locale, percentText)
            )
        default:
            return generic(locale)
        }
    }

    private static func generic(_ locale: Locale) -> (String, String) {
        (LocalizedText.string("insight.imbalance.generic.title", locale: locale), LocalizedText.string("insight.imbalance.generic.body", locale: locale))
    }

    // MARK: Helpers

    private static func name(_ id: String, names: [String: String], locale: Locale) -> String {
        names[id] ?? Muscle(rawValue: id)?.localizedName(locale: locale) ?? id
    }

    private static func muscleName(_ key: String, locale: Locale) -> String { Muscle(rawValue: key)?.localizedName(locale: locale) ?? key }

    private static func number(_ value: Double?, locale: Locale) -> String {
        (value ?? 0).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "+2,3 %" for a signed percentage, "86 %" for a share.
    private static func percent(_ value: Double?, locale: Locale, signed: Bool = true) -> String {
        guard let value else { return "–" }
        let text = abs(value).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return (signed ? (value < 0 ? "−" : "+") : "") + text + " %"
    }

    private static func icon(_ kind: InsightKind) -> String {
        switch kind {
        case .imbalance, .pushPull: "arrow.left.arrow.right"
        case .plateau: "pause.circle"
        case .progressFast: "arrow.up.right.circle"
        case .progressSlow: "tortoise"
        case .neglectedMuscle: "exclamationmark.triangle"
        case .comeback: "hand.wave"
        case .bodyweightStale: "scalemass"
        case .repRangeStuck: "repeat"
        }
    }
}
