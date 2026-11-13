import Foundation

/// How big a weight jump is meaningful for an exercise (docs/ANTRENMAN-MANTIGI.md §1).
public enum LoadClass: String, Sendable, CaseIterable {
    case lowerCompound, upperCompound, isolation

    /// Wished-for jump in kilograms before it is snapped to the plate step.
    public var baseIncrementKg: Double {
        switch self {
        case .lowerCompound: 5
        case .upperCompound: 2.5
        case .isolation: 1.25
        }
    }

    /// Classifies a catalog exercise. `isolation_*` patterns and `mechanic == "isolation"` are isolation; squat, hinge
    /// and olympic lifts are big lower-body compounds; everything else is an upper-body compound.
    public static func classify(movementPattern: String?, mechanic: String?) -> LoadClass {
        let pattern = movementPattern?.lowercased() ?? ""
        if pattern.hasPrefix("isolation_") || mechanic?.lowercased() == "isolation" { return .isolation }
        switch pattern {
        case "squat", "hip_hinge", "olympic": return .lowerCompound
        default: return .upperCompound
        }
    }
}

/// One completed working set of an earlier session.
public struct ProgressionSet: Sendable, Equatable {
    public let weightKg: Double
    public let reps: Int
    public let rir: Int?

    public init(weightKg: Double, reps: Int, rir: Int? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
    }
}

/// Everything the engine needs to know about one exercise.
public struct ProgressionInput: Sendable, Equatable {
    /// Earlier sessions, NEWEST first; each holds that session's completed working sets (warm-ups excluded).
    public var history: [[ProgressionSet]]
    public var repMin: Int
    public var repMax: Int
    /// The reps-in-reserve the program aims for; `ProgressionEngine.defaultTargetRir` when unset.
    public var targetRir: Int?
    public var loadClass: LoadClass
    /// Smallest loadable step in kilograms (one plate pair step; 2.5 kg or 5 lb).
    public var roundingStepKg: Double

    public init(
        history: [[ProgressionSet]], repMin: Int = ProgressionEngine.defaultRepRange.lowerBound,
        repMax: Int = ProgressionEngine.defaultRepRange.upperBound, targetRir: Int? = nil,
        loadClass: LoadClass = .upperCompound, roundingStepKg: Double = 2.5
    ) {
        self.history = history
        self.repMin = repMin
        self.repMax = max(repMax, repMin)
        self.targetRir = targetRir
        self.loadClass = loadClass
        self.roundingStepKg = roundingStepKg > 0 ? roundingStepKg : 2.5
    }
}

/// Why a suggestion looks the way it does. The app maps each case to a localized one-sentence template.
public enum ProgressionRationale: Sendable, Equatable {
    /// All sets reached the top of the rep range: the weight goes up by `incrementKg`, reps restart at the bottom.
    case addWeight(incrementKg: Double)
    /// The RIR was clearly easier than the target, so the jump is doubled.
    case addWeightFast(incrementKg: Double)
    /// Same weight, one more rep than the weakest set last time.
    case addRep
    /// RIR was clearly easier than the target: two more reps this time.
    case addRepsFast
    /// The last session was harder than the target RIR: stay put.
    case holdHard
    /// The last two sessions got worse: keep the load and recover.
    case recovery
    /// Three sessions in a row without progress: back off by 10%.
    case deload
    /// Bodyweight: one more rep than last time.
    case addRepBodyweight
}

/// The next session's target for one exercise: every working set is `weightKg × reps`.
public struct ProgressionSuggestion: Sendable, Equatable {
    public let weightKg: Double
    public let reps: Int
    public let rationale: ProgressionRationale

    public init(weightKg: Double, reps: Int, rationale: ProgressionRationale) {
        self.weightKg = weightKg
        self.reps = reps
        self.rationale = rationale
    }
}

/// "What should I do next workout?" (P043). Pure and deterministic; the rule table lives in docs/ANTRENMAN-MANTIGI.md.
public enum ProgressionEngine {
    public static let defaultRepRange = 8...12
    public static let defaultTargetRir = 2
    /// Deload keeps this share of the last top weight.
    public static let deloadFactor = 0.9
    /// A session counts as progress/regression when its performance moved by more than this share.
    static let noise = 0.01
    /// RIR this much above/below target is "clearly" easier/harder.
    static let rirMargin = 2

    private enum Trend { case progress, flat, regression }

    /// `nil` without any history (the caller falls back to the program's targets).
    public static func suggest(_ input: ProgressionInput) -> ProgressionSuggestion? {
        let sessions = input.history.filter { !$0.isEmpty }
        guard let latest = sessions.first else { return nil }
        let step = input.roundingStepKg
        let top = latest.map(\.weightKg).max() ?? 0

        if top <= 0 { return bodyweight(latest, input: input) }

        let trends = trends(of: sessions)
        // Three sessions in a row without progress: deload. Needs four sessions to see three comparisons.
        if trends.count >= 3, trends.prefix(3).allSatisfy({ $0 != .progress }) {
            let weight = max(snap(top * deloadFactor, step: step, rule: .toNearestOrAwayFromZero), step)
            return ProgressionSuggestion(weightKg: weight, reps: input.repMax, rationale: .deload)
        }
        // Two sessions in a row got worse: hold the load.
        if trends.count >= 2, trends.prefix(2).allSatisfy({ $0 == .regression }) {
            let reps = latest.filter { $0.weightKg == top }.map(\.reps).min() ?? input.repMin
            return ProgressionSuggestion(weightKg: top, reps: max(1, min(reps, input.repMax)), rationale: .recovery)
        }

        let atTop = latest.filter { $0.weightKg == top }
        let allAtCeiling = latest.allSatisfy { $0.weightKg == top && $0.reps >= input.repMax }
        let weakest = atTop.map(\.reps).min() ?? input.repMin
        let verdict = effort(of: latest, targetRir: input.targetRir ?? defaultTargetRir)
        let increment = increment(for: input.loadClass, step: step)

        if verdict == .harder {
            return ProgressionSuggestion(weightKg: top, reps: max(1, min(weakest, input.repMax)), rationale: .holdHard)
        }
        if allAtCeiling {
            let fast = verdict == .easier
            let jump = fast ? 2 * increment : increment
            return ProgressionSuggestion(
                weightKg: snap(top + jump, step: step, rule: .toNearestOrAwayFromZero), reps: input.repMin,
                rationale: fast ? .addWeightFast(incrementKg: jump) : .addWeight(incrementKg: jump)
            )
        }
        let bump = verdict == .easier ? 2 : 1
        let reps = max(1, min(weakest + bump, input.repMax))
        return ProgressionSuggestion(weightKg: top, reps: reps, rationale: verdict == .easier ? .addRepsFast : .addRep)
    }

    /// The weight jump for a class: its wished-for size snapped to the plate step, at least one step.
    public static func increment(for loadClass: LoadClass, step: Double) -> Double {
        max(snap(loadClass.baseIncrementKg, step: step, rule: .toNearestOrAwayFromZero), step)
    }

    // MARK: Helpers

    private enum Effort { case easier, onTarget, harder }

    /// Average logged RIR against the target; sets without RIR are ignored, no RIR at all is "on target".
    private static func effort(of sets: [ProgressionSet], targetRir: Int) -> Effort {
        let logged = sets.compactMap(\.rir)
        guard !logged.isEmpty else { return .onTarget }
        let average = Double(logged.reduce(0, +)) / Double(logged.count)
        if average >= Double(targetRir + rirMargin) { return .easier }
        if average <= Double(targetRir - 1) { return .harder }
        return .onTarget
    }

    /// Trend of each session against the one before it, newest comparison first.
    private static func trends(of sessions: [[ProgressionSet]]) -> [Trend] {
        guard sessions.count >= 2 else { return [] }
        return (0..<(sessions.count - 1)).map { index in
            let now = performance(of: sessions[index]), before = performance(of: sessions[index + 1])
            guard before > 0 else { return .progress }
            if now > before * (1 + noise) { return .progress }
            if now < before * (1 - noise) { return .regression }
            return .flat
        }
    }

    /// Best estimated 1RM of a session (best reps when it was all bodyweight).
    private static func performance(of sets: [ProgressionSet]) -> Double {
        let best = sets.compactMap { E1RMModel.standard.estimate(weightKg: $0.weightKg, reps: $0.reps)?.valueKg }.max()
        return best ?? Double(sets.map(\.reps).max() ?? 0)
    }

    private static func bodyweight(_ latest: [ProgressionSet], input: ProgressionInput) -> ProgressionSuggestion {
        let best = latest.map(\.reps).min() ?? input.repMin
        return ProgressionSuggestion(weightKg: 0, reps: max(best + 1, input.repMin), rationale: .addRepBodyweight)
    }

    private static func snap(_ value: Double, step: Double, rule: FloatingPointRoundingRule) -> Double {
        ((value / step * 1e9).rounded() / 1e9).rounded(rule) * step
    }
}
