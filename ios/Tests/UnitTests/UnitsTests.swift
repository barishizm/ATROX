import Foundation
import Testing

@testable import ATROX

@Suite struct WeightUnitTests {
    private let en = Locale(identifier: "en_US")
    private let tr = Locale(identifier: "tr_TR")

    @Test func kgToLbUsesMeasurementConversion() {
        #expect(abs(WeightUnit.pounds.value(fromKilograms: 100) - 220.462) < 0.001)
        #expect(WeightUnit.kilograms.value(fromKilograms: 82.5) == 82.5)
    }

    @Test func roundTripPreservesStoredKilograms() {
        for kg in [0.0, 2.5, 20, 61.234, 142.5] {
            let lb = WeightUnit.pounds.value(fromKilograms: kg)
            #expect(abs(WeightUnit.pounds.kilograms(from: lb) - kg) < 1e-9)
        }
    }

    @Test func formatsWithLocaleDecimalSeparator() {
        #expect(WeightFormat.string(kilograms: 82.5, unit: .kilograms, locale: en) == "82.5 kg")
        #expect(WeightFormat.string(kilograms: 82.5, unit: .kilograms, locale: tr) == "82,5 kg")
        #expect(WeightFormat.string(kilograms: 80, unit: .kilograms, locale: en) == "80 kg")
    }

    @Test func formatsPoundsAndTrimsToOneDecimal() {
        #expect(WeightFormat.string(kilograms: 100, unit: .pounds, locale: en) == "220.5 lb")
        #expect(WeightFormat.string(kilograms: 100, unit: .pounds, locale: tr) == "220,5 lb")
    }

    @Test func parsesUserInputToKilograms() throws {
        #expect(try #require(WeightFormat.kilograms(from: "82,5", unit: .kilograms, locale: tr)) == 82.5)
        let kg = try #require(WeightFormat.kilograms(from: "225", unit: .pounds, locale: en))
        #expect(abs(kg - 102.0582) < 0.001)
        #expect(WeightFormat.kilograms(from: "abc", unit: .kilograms, locale: en) == nil)
        #expect(WeightFormat.kilograms(from: "-5", unit: .kilograms, locale: en) == nil)
    }
}

@Suite struct LengthUnitTests {
    private let en = Locale(identifier: "en_US")
    private let tr = Locale(identifier: "tr_TR")

    @Test func centimetersToFeetInches() {
        let p = LengthFormat.feetInches(fromCentimeters: 180)
        #expect(p.feet == 5 && p.inches == 11)
        let q = LengthFormat.feetInches(fromCentimeters: 152.4)
        #expect(q.feet == 5 && q.inches == 0)
    }

    @Test func inchesNeverRoundTo12() {
        // 182.8 cm = 71.97 in -> rounds to 72 in = 6 ft 0 in, not 5 ft 12 in
        let p = LengthFormat.feetInches(fromCentimeters: 182.8)
        #expect(p.feet == 6 && p.inches == 0)
    }

    @Test func feetInchesToCentimeters() {
        #expect(abs(LengthFormat.centimeters(feet: 5, inches: 11) - 180.34) < 0.001)
        #expect(abs(LengthFormat.centimeters(feet: 6, inches: 0) - 182.88) < 0.001)
    }

    @Test func formatting() {
        #expect(LengthFormat.string(centimeters: 180, unit: .centimeters, locale: en) == "180 cm")
        #expect(LengthFormat.string(centimeters: 175.5, unit: .centimeters, locale: tr) == "175,5 cm")
        #expect(LengthFormat.string(centimeters: 180, unit: .feetInches, locale: en) == "5′ 11″")
    }

    @Test func measurementBackedConversion() {
        #expect(abs(LengthFormat.inches(fromCentimeters: 2.54) - 1) < 1e-9)
    }
}

@Suite struct PlateRoundingTests {
    @Test func stepsMatchPlateIncrements() {
        #expect(PlateRounding.step(for: .kilograms) == 2.5)
        #expect(PlateRounding.step(for: .pounds) == 5)
    }

    @Test(arguments: [
        (81.0, 80.0), (81.25, 82.5), (82.4, 82.5), (83.7, 82.5), (83.8, 85.0), (0.0, 0.0), (1.2, 0.0), (1.3, 2.5)
    ])
    func nearestKilogramStep(input: Double, expected: Double) {
        #expect(PlateRounding.nearest(kilograms: input, unit: .kilograms) == expected)
    }

    @Test func nearestPoundStepReturnsKilograms() {
        // 100 kg = 220.46 lb -> nearest 5 lb = 220 lb = 99.7903 kg
        let kg = PlateRounding.nearest(kilograms: 100, unit: .pounds)
        // Foundation uses 0.453592 kg/lb (~4e-5 kg error per 100 lb), so compare with a loose tolerance.
        #expect(abs(kg - 220 * 0.45359237) < 1e-3)
        #expect(abs(WeightUnit.pounds.value(fromKilograms: kg) - 220) < 1e-9)
    }

    @Test func tiesRoundUpAndDirectionalHelpers() {
        #expect(PlateRounding.nearest(kilograms: 1.25, unit: .kilograms) == 2.5)
        #expect(PlateRounding.down(kilograms: 84.9, unit: .kilograms) == 82.5)
        #expect(PlateRounding.up(kilograms: 82.6, unit: .kilograms) == 85)
        #expect(PlateRounding.up(kilograms: 85, unit: .kilograms) == 85)
    }

    @Test func invalidInputClampsToZero() {
        #expect(PlateRounding.nearest(kilograms: -3, unit: .kilograms) == 0)
        #expect(PlateRounding.nearest(kilograms: .nan, unit: .kilograms) == 0)
    }
}

@MainActor
@Suite struct LanguageSettingsTests {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return d
    }

    @Test func defaultsToSystem() {
        let s = LanguageSettings(defaults: defaults())
        #expect(s.language == .system)
        #expect(s.localeOverride == nil)
    }

    @Test func persistsChoiceAcrossInstances() {
        let d = defaults()
        let a = LanguageSettings(defaults: d)
        a.language = .turkish
        let b = LanguageSettings(defaults: d)
        #expect(b.language == .turkish)
        #expect(b.localeOverride?.identifier == "tr")
        a.language = .english
        #expect(LanguageSettings(defaults: d).localeOverride?.identifier == "en")
    }

    @Test func corruptStoredValueFallsBackToSystem() {
        let d = defaults()
        d.set("klingon", forKey: LanguageSettings.storageKey)
        #expect(LanguageSettings(defaults: d).language == .system)
    }

    @Test func effectiveLocaleFallsBackToSystemLocale() {
        let s = LanguageSettings(defaults: defaults())
        let sys = Locale(identifier: "de_DE")
        #expect(s.effectiveLocale(system: sys).identifier == "de_DE")
        s.language = .turkish
        #expect(s.effectiveLocale(system: sys).identifier == "tr")
    }
}

@Suite struct CatalogTests {
    @Test(arguments: ["en", "tr"]) func pluralVariantsResolve(lang: String) throws {
        let path = try #require(Bundle.main.path(forResource: lang, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let fmt = bundle.localizedString(forKey: "workout.summary.setCount %lld", value: nil, table: nil)
        let one = String(format: fmt, locale: Locale(identifier: lang), 1)
        let many = String(format: fmt, locale: Locale(identifier: lang), 5)
        if lang == "en" {
            #expect(one == "1 set" && many == "5 sets")
        } else {
            #expect(one == "1 set" && many == "5 set")
        }
    }
}
