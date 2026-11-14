import CoachKit
import DataKit
import DesignSystem
import Foundation

/// A proposal's card text, built from its JSON (the server already put names next to ids).
struct ProposalSummary: Equatable {
    struct Day: Equatable, Identifiable {
        let name: String
        let lines: [String]
        var id: String { name + lines.joined() }
    }

    let title: String
    let subtitle: String?
    /// One line per change / exercise, shown on the card.
    let lines: [String]
    /// Full per-day breakdown of a new routine (the preview sheet).
    let days: [Day]
    /// Names of exercises that load an area the user marked as limited.
    let warnings: [String]

    static func make(for proposal: CoachProposal, locale: Locale) -> ProposalSummary {
        func text(_ key: String, _ args: CVarArg...) -> String { LocalizedText.string(key, locale: locale, arguments: args) }
        let data = proposal.data
        let warnings = proposal.warnings.map { warning in
            text("coach.proposal.warning %@ %@", name(of: warning.exerciseId, in: data), areaName(warning.area, locale: locale))
        }
        switch proposal.kind {
        case .routine:
            let days = (data["days"]?.array ?? []).map { day in
                Day(name: day["name"]?.string ?? "", lines: (day["exercises"]?.array ?? []).map(exerciseLine))
            }
            let exerciseCount = days.reduce(0) { $0 + $1.lines.count }
            return ProposalSummary(
                title: data["name"]?.string ?? text("coach.proposal.routine.title"),
                subtitle: text("coach.proposal.routine.subtitle %lld %lld", days.count, exerciseCount),
                lines: days.map { "\($0.name): \($0.lines.count)" }, days: days, warnings: warnings
            )
        case .routineEdit:
            let lines = (data["operations"]?.array ?? []).map { operationLine($0, locale: locale) }
            return ProposalSummary(
                title: text("coach.proposal.edit.title"), subtitle: data["reason"]?.string ?? text("coach.proposal.edit.subtitle %lld", lines.count),
                lines: lines, days: [], warnings: warnings
            )
        case .exerciseSwap:
            let from = data["from"]?["name"]?.string ?? ""
            let to = data["to"]?["name"]?.string ?? ""
            return ProposalSummary(
                title: text("coach.proposal.swap.title"), subtitle: data["reason"]?.string,
                lines: ["\(from) → \(to)"], days: [], warnings: warnings
            )
        case .goalUpdate:
            var lines: [String] = []
            if let goal = data["goal"]?.string { lines.append(text("coach.proposal.goal.goal %@", goalName(goal, locale: locale))) }
            if let days = data["weekly_frequency"]?.int { lines.append(text("coach.proposal.goal.frequency %lld", days)) }
            return ProposalSummary(title: text("coach.proposal.goal.title"), subtitle: nil, lines: lines, days: [], warnings: [])
        case .memorySaved:
            return ProposalSummary(
                title: text("coach.proposal.memory.title"), subtitle: data["note"]?.string, lines: [], days: [], warnings: []
            )
        case .unknown:
            return ProposalSummary(title: text("coach.proposal.unknown.title"), subtitle: text("coach.proposal.unknown.subtitle"), lines: [], days: [], warnings: [])
        }
    }

    /// "Goblet Squat · 3×8–12"
    static func exerciseLine(_ item: CoachJSON) -> String {
        let name = item["name"]?.string ?? item["exercise_id"]?.string ?? "?"
        return "\(name) · \(prescription(item))"
    }

    static func prescription(_ item: CoachJSON) -> String {
        let sets = item["sets"]?.int.map(String.init) ?? "?"
        let low = item["reps_min"]?.int
        let high = item["reps_max"]?.int
        switch (low, high) {
        case let (low?, high?) where low != high: return "\(sets)×\(low)–\(high)"
        case let (low?, _): return "\(sets)×\(low)"
        default: return "\(sets) sets"
        }
    }

    private static func operationLine(_ operation: CoachJSON, locale: Locale) -> String {
        func text(_ key: String, _ args: CVarArg...) -> String { LocalizedText.string(key, locale: locale, arguments: args) }
        let exercise = operation["exercise_id"]?.string ?? "?"
        switch operation["op"]?.string {
        case "add": return text("coach.proposal.op.add %@", operation["exercise"].map(exerciseLine) ?? "?")
        case "remove": return text("coach.proposal.op.remove %@", exercise)
        case "replace": return text("coach.proposal.op.replace %@ %@", exercise, operation["with"].map(exerciseLine) ?? "?")
        case "update": return text("coach.proposal.op.update %@ %@", exercise, prescription(operation))
        default: return "?"
        }
    }

    private static func name(of id: String, in data: CoachJSON) -> String {
        func find(_ value: CoachJSON) -> String? {
            switch value {
            case .object(let object):
                if object["exercise_id"]?.string == id || object["id"]?.string == id, let name = object["name"]?.string { return name }
                return object.values.lazy.compactMap(find).first
            case .array(let items): return items.lazy.compactMap(find).first
            default: return nil
            }
        }
        return find(data) ?? id
    }

    private static func areaName(_ area: String, locale: Locale) -> String {
        let key = "coach.area.\(area)"
        let value = LocalizedText.string(key, locale: locale, arguments: [])
        return value == key ? area : value
    }

    private static func goalName(_ goal: String, locale: Locale) -> String {
        let key = "coach.goal.\(goal)"
        let value = LocalizedText.string(key, locale: locale, arguments: [])
        return value == key ? goal : value
    }
}
