import Foundation

/// One generated warm-up set. Weight is in the unit of the working weight passed to the generator.
public struct WarmupSet: Equatable, Sendable {
    public let weight: Double
    public let reps: Int
}

/// Builds a ramp of warm-up sets up to a working weight (empty bar, 40 %, 60 %, 80 %; reps fall as load rises).
public enum WarmupGenerator {
    public struct Step: Sendable {
        public let fraction: Double
        public let reps: Int

        public init(fraction: Double, reps: Int) {
            self.fraction = fraction
            self.reps = reps
        }
    }

    public static let defaultRamp: [Step] = [
        Step(fraction: 0.4, reps: 8), Step(fraction: 0.6, reps: 5), Step(fraction: 0.8, reps: 3)
    ]
    public static let barReps = 10

    /// - Parameters:
    ///   - workingWeight: Target working weight.
    ///   - bar: Bar weight; `0` for exercises without a bar (the ramp then starts at the first percentage).
    ///   - increment: Smallest plate jump (2.5 kg / 5 lb); every set is rounded to it.
    /// - Returns: Ascending sets, each strictly heavier than the one before and lighter than the working weight.
    ///   Empty when the working weight is not above the bar / increment.
    public static func sets(
        workingWeight: Double, bar: Double = 0, increment: Double, ramp: [Step] = defaultRamp
    ) -> [WarmupSet] {
        guard workingWeight.isFinite, workingWeight > 0, increment > 0 else { return [] }
        let bar = max(0, bar.isFinite ? bar : 0)
        var result: [WarmupSet] = []
        func append(_ weight: Double, _ reps: Int) {
            guard weight > (result.last?.weight ?? 0), weight < workingWeight else { return }
            result.append(WarmupSet(weight: weight, reps: reps))
        }
        if bar > 0 { append(bar, barReps) }
        for step in ramp {
            let rounded = (workingWeight * step.fraction / increment).rounded(.toNearestOrAwayFromZero) * increment
            append(max(rounded, bar), step.reps)
        }
        return result
    }
}
