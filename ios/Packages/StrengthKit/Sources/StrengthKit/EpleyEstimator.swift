import Foundation

/// Placeholder public type: estimates a one-rep max with the Epley formula.
/// The real estimator set lands with the StrengthKit steps (see docs/03-ML-MODEL.md).
public struct EpleyEstimator: Sendable {
    public init() {}

    /// - Parameters:
    ///   - weightKg: Load in kilograms (always kg, see CLAUDE.md).
    ///   - reps: Completed repetitions (>= 1).
    /// - Returns: Estimated 1RM in kilograms, or `nil` for invalid input.
    public func estimateOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}

/// An estimated one-rep max together with how much to trust it (docs/03-ML-MODEL.md §2, "güven ağırlığı").
public struct E1RMEstimate: Sendable, Equatable {
    public let valueKg: Double
    /// 0…1. 1 for 1–5 effective reps, falling to 0.6 at 12, 0.25 at 20 and 0 from 30; ×0.85 without a logged RIR.
    public let confidence: Double

    public init(valueKg: Double, confidence: Double) {
        self.valueKg = valueKg
        self.confidence = confidence
    }
}

extension EpleyEstimator {
    // TODO(P061): replace the Epley curve with the category-specific e1RM families of docs/03-ML-MODEL.md §2.
    /// e1RM of one set with its confidence weight. `r_eff = reps + RIR`; nil for invalid input or when the set is too
    /// long to say anything (`r_eff >= 30`, confidence 0).
    public func estimate(weightKg: Double, reps: Int, rir: Int? = nil) -> E1RMEstimate? {
        guard weightKg > 0, weightKg.isFinite, reps >= 1 else { return nil }
        let effective = reps + max(rir ?? 0, 0)
        let confidence = Self.confidence(effectiveReps: effective, hasRir: rir != nil)
        guard confidence > 0 else { return nil }
        let value = effective == 1 ? weightKg : weightKg * (1 + Double(effective) / 30)
        return E1RMEstimate(valueKg: value, confidence: confidence)
    }

    public static func confidence(effectiveReps: Int, hasRir: Bool) -> Double {
        let reps = Double(effectiveReps)
        let base: Double
        switch effectiveReps {
        case ..<1: base = 0
        case 1...5: base = 1
        case 6...12: base = 1 - 0.4 * (reps - 5) / 7
        case 13...20: base = 0.6 - 0.35 * (reps - 12) / 8
        case 21..<30: base = 0.25 - 0.25 * (reps - 20) / 10
        default: base = 0
        }
        return hasRir ? base : base * 0.85
    }
}
