import Foundation
import StrengthKit

/// Plate calculator settings (P039): default bar and the plates the user owns, kept per unit system.
enum PlatePreferences {
    static let barTypeKey = "workout.plates.bar"
    /// Custom bar weight, stored in kilograms like every other weight.
    static let customBarKgKey = "workout.plates.customBarKg"
    static func ownedKey(_ unit: PlateUnit) -> String { "workout.plates.owned.\(unit.rawValue)" }

    /// Pairs of each owned denomination used by the calculator.
    static let pairsPerPlate = 6

    static func plateUnit(_ unit: WeightUnit) -> PlateUnit { unit == .kilograms ? .kilograms : .pounds }

    static func barType(_ defaults: UserDefaults = .standard) -> BarType {
        defaults.string(forKey: barTypeKey).flatMap(BarType.init(rawValue:)) ?? .olympic20
    }

    /// Bar weight in the display unit.
    static func barWeight(unit: WeightUnit, defaults: UserDefaults = .standard) -> Double {
        let type = barType(defaults)
        if let fixed = type.weight(in: plateUnit(unit)) { return fixed }
        let kg = defaults.object(forKey: customBarKgKey) as? Double ?? 20
        return unit.value(fromKilograms: kg)
    }

    /// Owned denominations (display unit), heaviest first; every standard plate until the user changes it.
    static func ownedPlates(unit: PlateUnit, defaults: UserDefaults = .standard) -> [Double] {
        guard let text = defaults.string(forKey: ownedKey(unit)) else { return PlateDefaults.denominations(for: unit) }
        return decode(text).filter(PlateDefaults.denominations(for: unit).contains).sorted(by: >)
    }

    static func stock(unit: PlateUnit, defaults: UserDefaults = .standard) -> [PlateStock] {
        ownedPlates(unit: unit, defaults: defaults).map { PlateStock(weight: $0, pairs: pairsPerPlate) }
    }

    static func encode(_ plates: [Double]) -> String { plates.map { String($0) }.joined(separator: ",") }
    static func decode(_ text: String) -> [Double] { text.split(separator: ",").compactMap { Double($0) } }
}
