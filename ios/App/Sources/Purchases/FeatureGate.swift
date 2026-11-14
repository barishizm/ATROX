import Foundation
import StrengthKit

/// What Pro unlocks (P091, docs/00-KARARLAR.md "Pro kapsamı"). Workout logging, exercise and overall scores, basic
/// charts and the daily-limited coach are never behind a gate.
enum ProFeature: String, CaseIterable, Sendable {
    /// Near-unlimited coach messages (the quota itself is enforced by the server).
    case coachUnlimited
    /// Coach comments after workouts and weekly (server side).
    case proactiveCoach
    /// Progress forecast and plateau analysis in the e1RM chart.
    case forecast
    /// Full insight history.
    case fullInsightHistory
    /// General-population and competitor reference groups.
    case allReferenceGroups
    /// Advanced share cards.
    case advancedShareCards
}

extension ProFeature: Identifiable { var id: String { rawValue } }

/// The single place that decides whether something is locked. Views ask this with `Entitlements.isPro`.
enum FeatureGate {
    static func isLocked(_ feature: ProFeature, isPro: Bool) -> Bool { !isPro }

    /// Free users score against the gym reference group; the other two are Pro.
    static func isLocked(population: ReferencePopulation, isPro: Bool) -> Bool {
        population != .gym && isLocked(.allReferenceGroups, isPro: isPro)
    }

    /// Free users see the newest insights only; Pro sees all of them. The cut-off keeps recent history useful.
    static let freeInsightHistoryDays = 14

    static func insightHistoryCutoff(now: Date, isPro: Bool, calendar: Calendar = .current) -> Date? {
        guard isLocked(.fullInsightHistory, isPro: isPro) else { return nil }
        return calendar.date(byAdding: .day, value: -freeInsightHistoryDays, to: now)
    }
}
