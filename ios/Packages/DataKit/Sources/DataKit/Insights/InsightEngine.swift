import Foundation
import StrengthKit

// The insight engine (P069): turns StrengthKit findings (imbalance, plateau, progress) and a few simple training
// rules into ranked, text-free insight candidates. The app renders them with localized templates; the coach reads the
// same rows through `get_insights`. Pure: no storage, no UI.

public enum InsightKind: String, Sendable, Codable, CaseIterable {
    /// A StrengthKit imbalance finding (ratio rule, conditional residual or left/right).
    case imbalance
    case plateau
    case progressFast = "progress_fast"
    case progressSlow = "progress_slow"
    /// A muscle trained before but missing from the last 7 days.
    case neglectedMuscle = "neglected_muscle"
    /// Push and pull volume are far apart.
    case pushPull = "push_pull"
    /// Back after a long break.
    case comeback
    case bodyweightStale = "bodyweight_stale"
    /// Nearly every working set sits in one rep range.
    case repRangeStuck = "rep_range_stuck"
}

public enum InsightSeverity: String, Sendable, Codable, CaseIterable, Comparable {
    case mild, moderate, severe

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// What the card offers to do about it. One action per insight.
public enum InsightAction: String, Sendable, Codable {
    /// "Add a pulling exercise to your program": exercise suggestions for the weak muscles.
    case suggestExercises = "suggest_exercises"
    case askCoach = "ask_coach"
    case updateBodyweight = "update_bodyweight"
    case viewExercise = "view_exercise"
    case startWorkout = "start_workout"
}

/// The numbers and names behind an insight, kept free of text so the app can localize them. Stored as JSON.
public struct InsightPayload: Sendable, Codable, Equatable {
    /// Exercise ids or muscle keys the insight is about.
    public var subjects: [String]
    /// Muscle keys involved (for exercise suggestions).
    public var muscles: [String]
    public var values: [String: Double]
    /// Template variant, e.g. `pull_behind`, `strength`, `hypertrophy`.
    public var variant: String

    public init(subjects: [String] = [], muscles: [String] = [], values: [String: Double] = [:], variant: String = "") {
        self.subjects = subjects
        self.muscles = muscles
        self.values = values
        self.variant = variant
    }

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public init(json: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(json.utf8))) ?? InsightPayload()
    }
}

/// One thing worth telling the user, before it is stored or shown.
public struct InsightCandidate: Sendable, Equatable {
    public var kind: InsightKind
    /// What it is about (exercise id, muscle, rule id, or `global`); with the kind it identifies the insight.
    public var subject: String
    public var severity: InsightSeverity
    public var priority: Double
    public var payload: InsightPayload
    public var action: InsightAction
}

/// One exercise's progress facts.
public struct ExerciseProgressFact: Sendable, Equatable {
    public var exerciseId: String
    public var sessionCount: Int
    public var plateau: ProgressAnalyzer.PlateauStatus
    /// Progress score 0–100 (50 = as expected for the level); nil without enough data.
    public var progressScore: Double?
    public var observedMonthlyPct: Double?
    public var expectedMonthlyPct: Double?
    public var muscles: [String]

    public init(
        exerciseId: String, sessionCount: Int, plateau: ProgressAnalyzer.PlateauStatus, progressScore: Double?,
        observedMonthlyPct: Double? = nil, expectedMonthlyPct: Double? = nil, muscles: [String] = []
    ) {
        self.exerciseId = exerciseId
        self.sessionCount = sessionCount
        self.plateau = plateau
        self.progressScore = progressScore
        self.observedMonthlyPct = observedMonthlyPct
        self.expectedMonthlyPct = expectedMonthlyPct
        self.muscles = muscles
    }
}

/// Working sets per rep range over the last weeks.
public struct RepBandCounts: Sendable, Equatable {
    /// 1–5 reps.
    public var strength: Int
    /// 6–12 reps.
    public var hypertrophy: Int
    /// 13+ reps.
    public var endurance: Int

    public init(strength: Int = 0, hypertrophy: Int = 0, endurance: Int = 0) {
        self.strength = strength
        self.hypertrophy = hypertrophy
        self.endurance = endurance
    }

    public var total: Int { strength + hypertrophy + endurance }

    public mutating func add(reps: Int) {
        guard reps >= 1 else { return }
        if reps <= 5 { strength += 1 } else if reps <= 12 { hypertrophy += 1 } else { endurance += 1 }
    }
}

public struct InsightInputs: Sendable {
    public var imbalances: [ImbalanceAnalyzer.Finding]
    public var exercises: [ExerciseProgressFact]
    /// Weighted sets per muscle: four rolling weeks, oldest first (the last entry is the last 7 days).
    public var weeklyMuscleSets: [String: [Double]]
    public var finishedWorkouts: Int
    /// Days since the newest finished workout; nil without any.
    public var daysSinceLastWorkout: Int?
    /// Days since the last weigh-in once it is stale (> 60 days); nil while fresh or unknown.
    public var bodyweightStaleDays: Int?
    public var repBands: RepBandCounts

    public init(
        imbalances: [ImbalanceAnalyzer.Finding] = [], exercises: [ExerciseProgressFact] = [],
        weeklyMuscleSets: [String: [Double]] = [:], finishedWorkouts: Int = 0, daysSinceLastWorkout: Int? = nil,
        bodyweightStaleDays: Int? = nil, repBands: RepBandCounts = RepBandCounts()
    ) {
        self.imbalances = imbalances
        self.exercises = exercises
        self.weeklyMuscleSets = weeklyMuscleSets
        self.finishedWorkouts = finishedWorkouts
        self.daysSinceLastWorkout = daysSinceLastWorkout
        self.bodyweightStaleDays = bodyweightStaleDays
        self.repBands = repBands
    }
}

/// Thresholds of the rules. Below them an insight stays silent.
public enum InsightThresholds {
    public static let pushMuscles: Set<String> = ["chest", "shoulders", "triceps"]
    public static let pullMuscles: Set<String> = ["lats", "middle_back", "biceps", "traps"]

    /// Neglected muscle: no sets in the last 7 days after at least this many weekly sets over the 3 weeks before.
    public static let neglectedMinWeeklyAverage = 4.0
    /// Push/pull: push + pull need at least twice this many weighted sets in four weeks; the ratio ladder is mild /
    /// moderate / severe.
    public static let pushPullMinSets = 10.0
    public static let pushPullRatios = [1.6, 2.0, 3.0]
    /// Comeback: days away (needs at least `comebackMinWorkouts` finished workouts so new users are left alone).
    public static let comebackDays = [14, 30, 60]
    public static let comebackMinWorkouts = 3
    public static let bodyweightStaleDays = [60, 120, 240]
    /// Rep range: share of the sets in one range, with a minimum number of sets in the window.
    public static let repRangeShares = [0.85, 0.93, 0.98]
    public static let repRangeMinSets = 30
    /// Plateau / progress rules need this many sessions.
    public static let minSessions = 6
    /// Progress score bounds: at or below → slow, at or above → fast.
    public static let slowScore = 30.0
    public static let verySlowScore = 15.0
    public static let fastScore = 75.0
    /// Caps per kind so one theme does not flood the list.
    public static let capPerKind: [InsightKind: Int] = [
        .imbalance: 3, .plateau: 2, .progressFast: 1, .progressSlow: 2, .neglectedMuscle: 2,
    ]
    public static let basePriority: [InsightKind: Double] = [
        .comeback: 70, .imbalance: 60, .neglectedMuscle: 55, .pushPull: 52, .plateau: 50, .progressSlow: 45,
        .repRangeStuck: 35, .bodyweightStale: 30, .progressFast: 25,
    ]
}

public enum InsightEngine {
    /// Every insight the inputs justify, best first (priority, then kind and subject for a stable order).
    public static func candidates(_ inputs: InsightInputs) -> [InsightCandidate] {
        var out: [InsightCandidate] = []
        out += imbalance(inputs.imbalances)
        out += plateau(inputs.exercises)
        out += progress(inputs.exercises)
        out += neglected(inputs.weeklyMuscleSets)
        out += pushPull(inputs.weeklyMuscleSets, imbalances: inputs.imbalances)
        out += comeback(inputs)
        out += bodyweight(inputs.bodyweightStaleDays)
        out += repRange(inputs.repBands)
        return out.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.kind.rawValue, $0.subject) < ($1.kind.rawValue, $1.subject)
        }
    }

    static func priority(_ kind: InsightKind, _ severity: InsightSeverity, extra: Double = 0) -> Double {
        (InsightThresholds.basePriority[kind] ?? 0) + Double(severity.rank) * 10 + min(max(extra, 0), 9.9)
    }

    private static func severity(_ value: Double, ladder: [Double]) -> InsightSeverity? {
        var out: InsightSeverity?
        for (level, threshold) in zip(InsightSeverity.allCases, ladder) where value >= threshold { out = level }
        return out
    }

    private static func capped(_ items: [InsightCandidate], _ kind: InsightKind) -> [InsightCandidate] {
        let sorted = items.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.subject < $1.subject }
        return Array(sorted.prefix(InsightThresholds.capPerKind[kind] ?? sorted.count))
    }

    // MARK: Rules

    static func imbalance(_ findings: [ImbalanceAnalyzer.Finding]) -> [InsightCandidate] {
        capped(findings.map { finding in
            let level = InsightSeverity(rawValue: finding.severity.rawValue) ?? .mild
            return InsightCandidate(
                kind: .imbalance, subject: "\(finding.kind.rawValue).\(finding.ruleId)", severity: level,
                priority: priority(.imbalance, level, extra: finding.magnitude),
                payload: InsightPayload(
                    subjects: Array(finding.weakExerciseIds.prefix(3)), muscles: finding.muscles,
                    values: ["magnitude": finding.magnitude], variant: finding.recommendationKey
                ),
                action: finding.kind == .leftRight ? .askCoach : .suggestExercises
            )
        }, .imbalance)
    }

    static func plateau(_ facts: [ExerciseProgressFact]) -> [InsightCandidate] {
        capped(facts.filter { $0.plateau == .plateau && $0.sessionCount >= InsightThresholds.minSessions }.map { fact in
            let level: InsightSeverity = (fact.progressScore ?? 50) <= InsightThresholds.slowScore ? .moderate : .mild
            return InsightCandidate(
                kind: .plateau, subject: fact.exerciseId, severity: level, priority: priority(.plateau, level, extra: Double(fact.sessionCount) / 10),
                payload: InsightPayload(subjects: [fact.exerciseId], muscles: fact.muscles, values: ["sessions": Double(fact.sessionCount)]),
                action: .askCoach
            )
        }, .plateau)
    }

    static func progress(_ facts: [ExerciseProgressFact]) -> [InsightCandidate] {
        var slow: [InsightCandidate] = [], fast: [InsightCandidate] = []
        for fact in facts where fact.sessionCount >= InsightThresholds.minSessions {
            guard let score = fact.progressScore else { continue }
            var values = ["score": score]
            if let observed = fact.observedMonthlyPct { values["observed_pct"] = observed * 100 }
            if let expected = fact.expectedMonthlyPct { values["expected_pct"] = expected * 100 }
            if score <= InsightThresholds.slowScore, fact.plateau != .plateau {
                let level: InsightSeverity = score <= InsightThresholds.verySlowScore ? .moderate : .mild
                slow.append(InsightCandidate(
                    kind: .progressSlow, subject: fact.exerciseId, severity: level,
                    priority: priority(.progressSlow, level, extra: (InsightThresholds.slowScore - score) / 5),
                    payload: InsightPayload(subjects: [fact.exerciseId], muscles: fact.muscles, values: values), action: .askCoach
                ))
            } else if score >= InsightThresholds.fastScore {
                fast.append(InsightCandidate(
                    kind: .progressFast, subject: fact.exerciseId, severity: .mild,
                    priority: priority(.progressFast, .mild, extra: (score - InsightThresholds.fastScore) / 5),
                    payload: InsightPayload(subjects: [fact.exerciseId], muscles: fact.muscles, values: values), action: .viewExercise
                ))
            }
        }
        return capped(slow, .progressSlow) + capped(fast, .progressFast)
    }

    static func neglected(_ weekly: [String: [Double]]) -> [InsightCandidate] {
        capped(weekly.keys.sorted().compactMap { muscle in
            guard let weeks = weekly[muscle], weeks.count == 4, weeks[3] == 0 else { return nil }
            let average = (weeks[0] + weeks[1] + weeks[2]) / 3
            guard average >= InsightThresholds.neglectedMinWeeklyAverage else { return nil }
            let level: InsightSeverity = weeks[2] == 0 ? .moderate : .mild
            return InsightCandidate(
                kind: .neglectedMuscle, subject: muscle, severity: level, priority: priority(.neglectedMuscle, level, extra: average / 2),
                payload: InsightPayload(subjects: [muscle], muscles: [muscle], values: ["weekly_average": average]), action: .suggestExercises
            )
        }, .neglectedMuscle)
    }

    static func pushPull(_ weekly: [String: [Double]], imbalances: [ImbalanceAnalyzer.Finding]) -> [InsightCandidate] {
        // The StrengthKit push/pull ratio rule already says it from the strength side.
        guard !imbalances.contains(where: { $0.kind == .ratioRule && $0.ruleId == "push_pull" }) else { return [] }
        func total(_ muscles: Set<String>) -> Double { muscles.reduce(0) { $0 + (weekly[$1]?.reduce(0, +) ?? 0) } }
        let push = total(InsightThresholds.pushMuscles), pull = total(InsightThresholds.pullMuscles)
        guard push + pull >= InsightThresholds.pushPullMinSets * 2 else { return [] }
        let ratio = max(push, pull) / max(min(push, pull), 1)
        guard let level = severity(ratio, ladder: InsightThresholds.pushPullRatios) else { return [] }
        let pullBehind = pull < push
        return [InsightCandidate(
            kind: .pushPull, subject: "push_pull", severity: level, priority: priority(.pushPull, level, extra: ratio),
            payload: InsightPayload(
                subjects: [], muscles: Array((pullBehind ? InsightThresholds.pullMuscles : InsightThresholds.pushMuscles).sorted()),
                values: ["push_sets": push, "pull_sets": pull, "ratio": ratio], variant: pullBehind ? "pull_behind" : "push_behind"
            ),
            action: .suggestExercises
        )]
    }

    static func comeback(_ inputs: InsightInputs) -> [InsightCandidate] {
        guard let days = inputs.daysSinceLastWorkout, inputs.finishedWorkouts >= InsightThresholds.comebackMinWorkouts,
              let level = severity(Double(days), ladder: InsightThresholds.comebackDays.map(Double.init)) else { return [] }
        return [InsightCandidate(
            kind: .comeback, subject: "global", severity: level, priority: priority(.comeback, level),
            payload: InsightPayload(values: ["days": Double(days)]), action: .startWorkout
        )]
    }

    static func bodyweight(_ staleDays: Int?) -> [InsightCandidate] {
        guard let days = staleDays, let level = severity(Double(days), ladder: InsightThresholds.bodyweightStaleDays.map(Double.init)) else { return [] }
        return [InsightCandidate(
            kind: .bodyweightStale, subject: "global", severity: level, priority: priority(.bodyweightStale, level),
            payload: InsightPayload(values: ["days": Double(days)]), action: .updateBodyweight
        )]
    }

    static func repRange(_ bands: RepBandCounts) -> [InsightCandidate] {
        guard bands.total >= InsightThresholds.repRangeMinSets else { return [] }
        let options = [("strength", bands.strength), ("hypertrophy", bands.hypertrophy), ("endurance", bands.endurance)]
        guard let top = options.max(by: { $0.1 < $1.1 }) else { return [] }
        let share = Double(top.1) / Double(bands.total)
        guard let level = severity(share, ladder: InsightThresholds.repRangeShares) else { return [] }
        return [InsightCandidate(
            kind: .repRangeStuck, subject: "global", severity: level, priority: priority(.repRangeStuck, level),
            payload: InsightPayload(values: ["share": share, "sets": Double(bands.total)], variant: top.0), action: .askCoach
        )]
    }
}

// MARK: - Showing

/// A stored insight as the app sees it.
public struct Insight: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: InsightKind
    public var subject: String
    public var severity: InsightSeverity
    public var priority: Double
    public var action: InsightAction
    public var payload: InsightPayload
    /// The condition holds right now.
    public var isActive: Bool
    public var detectedAt: Date
    public var lastShownAt: Date?
    public var dismissedAt: Date?

    public init(
        id: UUID, kind: InsightKind, subject: String, severity: InsightSeverity, priority: Double, action: InsightAction,
        payload: InsightPayload, isActive: Bool, detectedAt: Date, lastShownAt: Date? = nil, dismissedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.severity = severity
        self.priority = priority
        self.action = action
        self.payload = payload
        self.isActive = isActive
        self.detectedAt = detectedAt
        self.lastShownAt = lastShownAt
        self.dismissedAt = dismissedAt
    }
}

public enum InsightSelector {
    /// The same insight is not shown on Today again within this many days of its first showing.
    public static let repeatSuppressionDays = 14
    /// A dismissed insight stays away this long (and comes back only if its condition still holds after that).
    public static let dismissSuppressionDays = 60

    /// Candidates the Today card may pick: active, not dismissed recently, and either never shown, shown today (the
    /// card stays stable during the day) or last shown at least `repeatSuppressionDays` ago.
    public static func isEligible(_ insight: Insight, now: Date, calendar: Calendar = .current) -> Bool {
        guard insight.isActive else { return false }
        if let dismissed = insight.dismissedAt, days(from: dismissed, to: now, calendar: calendar) < dismissSuppressionDays { return false }
        guard let shown = insight.lastShownAt else { return true }
        if calendar.isDate(shown, inSameDayAs: now) { return true }
        return days(from: shown, to: now, calendar: calendar) >= repeatSuppressionDays
    }

    /// The single most important eligible insight (priority, then severity, kind and subject for stability).
    public static func top(_ insights: [Insight], now: Date, calendar: Calendar = .current) -> Insight? {
        insights.filter { isEligible($0, now: now, calendar: calendar) }.min {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.kind.rawValue, $0.subject) < ($1.kind.rawValue, $1.subject)
        }
    }

    /// Active insights the user has not dismissed (the full list on Analysis), best first.
    public static func current(_ insights: [Insight], now: Date, calendar: Calendar = .current) -> [Insight] {
        insights.filter { insight in
            guard insight.isActive else { return false }
            if let dismissed = insight.dismissedAt, days(from: dismissed, to: now, calendar: calendar) < dismissSuppressionDays { return false }
            return true
        }.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.id.uuidString < $1.id.uuidString }
    }

    /// Dismissed or no longer applicable insights, newest first (history).
    public static func history(_ insights: [Insight], now: Date, calendar: Calendar = .current) -> [Insight] {
        let live = Set(current(insights, now: now, calendar: calendar).map(\.id))
        return insights.filter { !live.contains($0.id) }.sorted { $0.detectedAt > $1.detectedAt }
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
