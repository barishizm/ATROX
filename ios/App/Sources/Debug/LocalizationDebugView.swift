#if DEBUG
import DesignSystem
import SwiftUI

/// Debug-only: switch the in-app language and eyeball unit formatting, plate rounding and plural rules.
struct LocalizationDebugView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var unit: WeightUnit = .kilograms
    @State private var length: LengthUnit = .centimeters
    private let sampleKg = 83.7
    private let sampleCm = 180.0

    var body: some View {
        @Bindable var language = container.language
        List {
            Section("settings.language.title") {
                Picker("settings.language.title", selection: $language.language) {
                    ForEach(AppLanguage.allCases) { option in
                        if let name = option.nativeName {
                            Text(verbatim: name).tag(option)
                        } else {
                            Text("settings.language.system").tag(option)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("l10n-language-picker")
            }
            Section("debug.l10n.weight") {
                Picker("debug.l10n.weight", selection: $unit) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text(verbatim: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                row("83.7", WeightFormat.string(kilograms: sampleKg, unit: unit, locale: locale))
                Text("debug.l10n.plate").foregroundStyle(DSColor.textSecondary)
                row("→", WeightFormat.string(
                    kilograms: PlateRounding.nearest(kilograms: sampleKg, unit: unit), unit: unit, locale: locale))
            }
            Section("debug.l10n.height") {
                Picker("debug.l10n.height", selection: $length) {
                    Text(verbatim: "cm").tag(LengthUnit.centimeters)
                    Text(verbatim: "ft/in").tag(LengthUnit.feetInches)
                }
                .pickerStyle(.segmented)
                row("180", LengthFormat.string(centimeters: sampleCm, unit: length, locale: locale))
            }
            Section("debug.l10n.plural") {
                ForEach([0, 1, 2, 5], id: \.self) { n in
                    Text("workout.summary.setCount \(n)")
                }
            }
        }
        .navigationTitle("debug.menu.localization")
        .accessibilityIdentifier("l10n-debug")
    }

    private func row(_ input: String, _ output: String) -> some View {
        HStack {
            Text(verbatim: input + " kg/cm").foregroundStyle(DSColor.textSecondary)
            Spacer()
            Text(verbatim: output).font(DSFont.headline)
        }
    }
}
#endif
