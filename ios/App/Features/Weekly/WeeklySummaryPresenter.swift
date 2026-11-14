import DataKit
import Foundation

/// One story card of the weekly summary (also a row of the list view).
struct WeeklyCard: Identifiable, Equatable {
    enum Kind: String { case workouts, volume, records, scores, muscles, insight, coach, restart }

    let kind: Kind
    let icon: String
    let title: String
    /// The big number or phrase; empty for text-only cards.
    let value: String
    let lines: [String]
    /// The coach's comment is still being written (P083): the card shows a skeleton.
    var isLoading = false

    var id: String { kind.rawValue }
}

/// What the coach card shows (P083). Anything but a ready comment keeps the card out of the list.
enum CoachCardState: Equatable {
    case hidden
    case loading
    case text(String)
}

/// Turns a `WeeklySummary` into localized text (P070).
enum WeeklySummaryPresenter {
    static func cards(
        for summary: WeeklySummary, names: [String: String], locale: Locale, insight: InsightItem?, coach state: CoachCardState = .hidden
    ) -> [WeeklyCard] {
        func text(_ key: String, _ args: CVarArg...) -> String {
            LocalizedText.string(key, locale: locale, arguments: args)
        }
        let coach: [WeeklyCard]
        switch state {
        case .hidden: coach = []
        case .loading:
            coach = [WeeklyCard(kind: .coach, icon: "bubble.left.and.text.bubble.right", title: text("weekly.card.coach"), value: "", lines: [], isLoading: true)]
        case .text(let comment):
            coach = [WeeklyCard(kind: .coach, icon: "bubble.left.and.text.bubble.right", title: text("weekly.card.coach"), value: "", lines: [comment])]
        }
        guard !summary.isEmpty else {
            return [
                WeeklyCard(kind: .restart, icon: "arrow.clockwise", title: text("weekly.restart.title"), value: "", lines: [text("weekly.restart.body")])
            ] + coach
        }
        var cards: [WeeklyCard] = []
        let goalLine = summary.metGoal ? text("weekly.workouts.met") : text("weekly.workouts.left %lld", summary.goal - summary.workouts)
        cards.append(WeeklyCard(kind: .workouts, icon: "figure.strengthtraining.traditional", title: text("weekly.card.workouts"), value: "\(summary.workouts)/\(summary.goal)", lines: [goalLine]))
        var volumeLines = [text("weekly.volume.sets %lld", summary.totalSets)]
        volumeLines.append(summary.volumeChange.map { text("weekly.volume.change %@", signed($0)) } ?? text("weekly.volume.nocompare"))
        cards.append(WeeklyCard(kind: .volume, icon: "chart.bar.fill", title: text("weekly.card.volume"), value: "\(summary.totalSets)", lines: volumeLines))
        if !summary.records.isEmpty {
            let lines = summary.records.prefix(4).map { "\(names[$0.exerciseId] ?? $0.exerciseId) · \(text("weekly.record.\($0.kind.rawValue)"))" }
            cards.append(WeeklyCard(kind: .records, icon: "trophy.fill", title: text("weekly.card.records"), value: "\(summary.records.count)", lines: lines))
        }
        if let overall = summary.overallScore {
            var lines = [text("weekly.scores.overall %lld", Int(overall.rounded()))]
            lines += summary.exerciseChanges.map { "\(names[$0.key] ?? $0.key): \(signed($0.change))" }
            cards.append(WeeklyCard(kind: .scores, icon: "gauge.with.dots.needle.67percent", title: text("weekly.card.scores"), value: summary.overallChange.map(signed) ?? "–", lines: lines))
        }
        if let top = summary.topGroup {
            var lines = [text("weekly.muscles.top %@", text("weekly.group.\(top.rawValue)"))]
            if !summary.neglectedGroups.isEmpty {
                lines.append(text("weekly.muscles.neglected %@", summary.neglectedGroups.map { text("weekly.group.\($0.rawValue)") }.joined(separator: ", ")))
            }
            cards.append(WeeklyCard(kind: .muscles, icon: "figure.arms.open", title: text("weekly.card.muscles"), value: text("weekly.group.\(top.rawValue)"), lines: lines))
        }
        if let insight {
            cards.append(WeeklyCard(kind: .insight, icon: insight.icon, title: text("weekly.card.insight"), value: "", lines: [insight.title, insight.body]))
        }
        return cards + coach
    }

    /// "9 Nov – 15 Nov".
    static func rangeTitle(_ period: WeekPeriod, locale: Locale, calendar: Calendar = .current) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        let style = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.abbreviated)
        return "\(period.start.formatted(style)) – \(last.formatted(style))"
    }

    /// Title and body of the Sunday notification; a week without workouts gets the gentle restart line.
    static func notification(for summary: WeeklySummary?, locale: Locale) -> (title: String, body: String) {
        let title = LocalizedText.string("weekly.notification.title", locale: locale)
        guard let summary, !summary.isEmpty else { return (title, LocalizedText.string("weekly.notification.empty", locale: locale)) }
        let key = summary.records.isEmpty ? "weekly.notification.body %lld %lld" : "weekly.notification.body.records %lld %lld %lld"
        let body = summary.records.isEmpty
            ? LocalizedText.string(key, locale: locale, arguments: [summary.workouts, summary.goal] as [CVarArg])
            : LocalizedText.string(key, locale: locale, arguments: [summary.workouts, summary.goal, summary.records.count] as [CVarArg])
        return (title, body)
    }

    private static func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}
