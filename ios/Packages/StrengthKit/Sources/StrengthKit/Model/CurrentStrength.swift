import Foundation

/// Current strength of one exercise (docs/03-ML-MODEL.md §3), from `gymml.scoring.current_strength`.
public struct CurrentStrength: Sendable, Equatable {
    /// e1RM in the exercise's logged unit (effective load for bodyweight moves); nil without accepted sessions.
    public var e1rmKg: Double?
    public var confidence: ScoreConfidence
    /// No session inside the window: the value is the decayed best.
    public var stale: Bool
    public var sessionsInWindow: Int
    /// Days whose jump (> outlier threshold) waits for the user's confirmation.
    public var flaggedDays: [Int]

    public init(e1rmKg: Double?, confidence: ScoreConfidence, stale: Bool, sessionsInWindow: Int, flaggedDays: [Int] = []) {
        self.e1rmKg = e1rmKg
        self.confidence = confidence
        self.stale = stale
        self.sessionsInWindow = sessionsInWindow
        self.flaggedDays = flaggedDays
    }
}

extension StrengthModel {
    struct SessionValue {
        let day: Int
        let e1rmKg: Double
        let confidence: Double
        let confirmed: Bool
    }

    /// Per day, the set with the largest e1RM × confidence (ties: larger e1RM, then the first logged).
    func sessionValues(_ ex: TaxonomyExercise, _ sets: [ScoringSet], user: ScoringUser) throws(StrengthModelError)
        -> [SessionValue] {
        var best: [Int: SessionValue] = [:]
        for set in sets {
            let est = try scoreSet(ex, set, user: user)
            guard est.confidence >= params.currentStrength.minSetConfidence else { continue }
            let candidate = SessionValue(day: set.day, e1rmKg: est.valueKg, confidence: est.confidence, confirmed: set.confirmed)
            if let current = best[set.day] {
                let lhs = (candidate.e1rmKg * candidate.confidence, candidate.e1rmKg)
                let rhs = (current.e1rmKg * current.confidence, current.e1rmKg)
                if lhs > rhs { best[set.day] = candidate }
            } else {
                best[set.day] = candidate
            }
        }
        return best.values.sorted { $0.day < $1.day }
    }

    public func currentStrength(exerciseId: String, sets: [ScoringSet], user: ScoringUser, asOfDay: Int) throws(StrengthModelError)
        -> CurrentStrength {
        try currentStrength(exercise(exerciseId), sets: sets, user: user.validated(), asOfDay: asOfDay)
    }

    public func currentStrength(_ ex: TaxonomyExercise, sets: [ScoringSet], user: ScoringUser, asOfDay: Int) throws(StrengthModelError)
        -> CurrentStrength {
        let cfg = params.currentStrength
        let sessions = try sessionValues(ex, sets, user: user).filter { $0.day <= asOfDay }
        var accepted: [SessionValue] = []
        var flagged: [Int] = []
        for value in sessions {
            if let prev = accepted.map(\.e1rmKg).max(), value.e1rmKg > prev * (1 + cfg.outlierJump), !value.confirmed {
                flagged.append(value.day)
                continue
            }
            accepted.append(value)
        }
        guard let last = accepted.map(\.day).max() else {
            return CurrentStrength(e1rmKg: nil, confidence: .low, stale: false, sessionsInWindow: 0, flaggedDays: flagged)
        }
        let window = accepted.filter { asOfDay - $0.day <= cfg.windowDays }
        let value: Double, stale: Bool
        if let best = firstMax(window, by: \.e1rmKg) {
            (value, stale) = (best.e1rmKg, false)
        } else {
            let decayed = accepted.map { session -> Double in
                let weeks = max(0, Double(asOfDay - session.day - cfg.windowDays) / 7)
                return session.e1rmKg * pow(1 - cfg.staleDecayPerWeek, weeks)
            }
            (value, stale) = (decayed.max() ?? 0, true)
        }
        let used = window.isEmpty ? accepted : window
        let meanConf = used.map(\.confidence).reduce(0, +) / Double(used.count)
        var level = confidenceLevel(sessions: window.count, daysSinceLast: asOfDay - last, meanConfidence: meanConf)
        if stale { level = .low }
        return CurrentStrength(e1rmKg: value, confidence: level, stale: stale, sessionsInWindow: window.count, flaggedDays: flagged)
    }

    private func confidenceLevel(sessions: Int, daysSinceLast: Int, meanConfidence: Double) -> ScoreConfidence {
        for level in [ScoreConfidence.high, .medium] {
            guard let rule = params.currentStrength.confidenceLevels[level.rawValue] else { continue }
            if sessions >= rule.minSessions, daysSinceLast <= rule.maxDaysSinceLast, meanConfidence >= rule.minMeanSetConfidence {
                return level
            }
        }
        return .low
    }
}

/// First element with the maximum key (Python `max` semantics).
func firstMax<T>(_ items: [T], by key: (T) -> Double) -> T? {
    var best: T?
    var bestKey = -Double.infinity
    for item in items where best == nil || key(item) > bestKey {
        best = item
        bestKey = key(item)
    }
    return best
}
