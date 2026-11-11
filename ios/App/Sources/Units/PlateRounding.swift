import Foundation

/// Rounds loads to the smallest available plate increment (2.5 kg / 5 lb).
/// Rounding happens in the user's display unit; results are returned in stored kilograms.
enum PlateRounding {
    static func step(for unit: WeightUnit) -> Double {
        unit == .kilograms ? 2.5 : 5
    }

    static func nearest(kilograms: Double, unit: WeightUnit) -> Double {
        apply(kilograms, unit) { ($0).rounded(.toNearestOrAwayFromZero) }
    }

    static func down(kilograms: Double, unit: WeightUnit) -> Double {
        apply(kilograms, unit) { $0.rounded(.down) }
    }

    static func up(kilograms: Double, unit: WeightUnit) -> Double {
        apply(kilograms, unit) { $0.rounded(.up) }
    }

    private static func apply(_ kg: Double, _ unit: WeightUnit, _ rule: (Double) -> Double) -> Double {
        guard kg.isFinite, kg > 0 else { return 0 }
        let step = step(for: unit)
        let inUnit = unit.value(fromKilograms: kg)
        // Epsilon guards against 220.00000000001 lb style float noise before floor/ceil.
        let steps = rule((inUnit / step * 1e9).rounded() / 1e9)
        return unit.kilograms(from: steps * step)
    }
}
