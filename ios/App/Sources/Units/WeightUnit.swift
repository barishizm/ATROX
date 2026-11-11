import Foundation

/// Display unit for body/barbell weight. Storage is ALWAYS kilograms; conversion happens only for display/input.
enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kilograms
    case pounds

    var unit: UnitMass { self == .kilograms ? .kilograms : .pounds }
    var symbol: String { self == .kilograms ? "kg" : "lb" }

    /// Stored kg -> value in this unit.
    func value(fromKilograms kg: Double) -> Double {
        Measurement(value: kg, unit: UnitMass.kilograms).converted(to: unit).value
    }

    /// Value in this unit -> stored kg.
    func kilograms(from value: Double) -> Double {
        Measurement(value: value, unit: unit).converted(to: .kilograms).value
    }

    /// Default for a region: pounds in the US, Liberia and Myanmar, kilograms elsewhere.
    static func `default`(for locale: Locale) -> WeightUnit {
        locale.measurementSystem == .us ? .pounds : .kilograms
    }
}

enum WeightFormat {
    /// "82,5 kg" / "220.5 lb" — at most one decimal, locale-aware separator.
    static func string(kilograms: Double, unit: WeightUnit, locale: Locale) -> String {
        let value = unit.value(fromKilograms: kilograms)
        let number = value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(number) \(unit.symbol)"
    }

    /// Parses user input in `unit` into stored kilograms. Returns nil for non-numeric or negative input.
    static func kilograms(from text: String, unit: WeightUnit, locale: Locale) -> Double? {
        guard let value = try? Double(text.trimmingCharacters(in: .whitespaces), format: .number.locale(locale)),
              value.isFinite, value >= 0 else { return nil }
        return unit.kilograms(from: value)
    }
}
