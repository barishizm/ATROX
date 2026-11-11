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
