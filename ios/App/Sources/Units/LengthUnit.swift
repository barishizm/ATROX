import Foundation

/// Display unit for height. Storage is ALWAYS centimeters.
enum LengthUnit: String, CaseIterable, Codable, Sendable {
    case centimeters
    case feetInches

    static func `default`(for locale: Locale) -> LengthUnit {
        locale.measurementSystem == .us ? .feetInches : .centimeters
    }
}

enum LengthFormat {
    static func inches(fromCentimeters cm: Double) -> Double {
        Measurement(value: cm, unit: UnitLength.centimeters).converted(to: .inches).value
    }

    static func centimeters(feet: Int, inches: Int) -> Double {
        let totalInches = Measurement(value: Double(feet * 12 + inches), unit: UnitLength.inches)
        return totalInches.converted(to: .centimeters).value
    }

    /// Whole feet + inches, rounding to the nearest inch (carries 12 in into the next foot).
    static func feetInches(fromCentimeters cm: Double) -> (feet: Int, inches: Int) {
        let total = Int(inches(fromCentimeters: max(0, cm.isFinite ? cm : 0)).rounded())
        return (total / 12, total % 12)
    }

    /// "180 cm" / "175,5 cm" / `5′ 11″`.
    static func string(centimeters cm: Double, unit: LengthUnit, locale: Locale) -> String {
        switch unit {
        case .centimeters:
            let number = cm.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            return "\(number) cm"
        case .feetInches:
            let p = feetInches(fromCentimeters: cm)
            return "\(p.feet)′ \(p.inches)″"
        }
    }
}
