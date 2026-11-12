import DesignSystem
import StrengthKit
import SwiftUI

/// Plate calculator (P039): target weight + bar + owned plates -> plates per side, with the nearest lower/upper
/// load when the target cannot be built exactly. Opens from a long press on a set's weight.
struct PlateCalculatorView: View {
    let unit: WeightUnit
    let initialWeight: Double
    let onApply: ((Double) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlatePreferences.barTypeKey) private var barTypeRaw = BarType.olympic20.rawValue
    @AppStorage(PlatePreferences.customBarKgKey) private var customBarKg = 20.0
    @State private var target: Double

    init(unit: WeightUnit, initialWeight: Double, onApply: ((Double) -> Void)? = nil) {
        self.unit = unit
        self.initialWeight = initialWeight
        self.onApply = onApply
        _target = State(initialValue: initialWeight)
    }

    private var plateUnit: PlateUnit { PlatePreferences.plateUnit(unit) }
    private var barType: BarType { BarType(rawValue: barTypeRaw) ?? .olympic20 }
    private var step: Double { PlateRounding.step(for: unit) }
    private var bar: Double { barType.weight(in: plateUnit) ?? unit.value(fromKilograms: customBarKg) }
    private var solution: PlateSolution {
        PlateCalculator.solve(target: target, bar: bar, stock: PlatePreferences.stock(unit: plateUnit))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("plates.target") {
                    Stepper(value: $target, in: 0...1000, step: step) {
                        Text(verbatim: "\(Self.format(target)) \(unit.symbol)").font(DSFont.numericMedium).monospacedDigit()
                    }
                    .accessibilityIdentifier("plates-target")
                }
                Section("plates.bar") {
                    Picker("plates.bar", selection: $barTypeRaw) {
                        ForEach(BarType.allCases, id: \.rawValue) { type in
                            Text(verbatim: label(type)).tag(type.rawValue)
                        }
                    }
                    if barType == .custom {
                        Stepper(value: Binding(
                            get: { unit.value(fromKilograms: customBarKg) },
                            set: { customBarKg = unit.kilograms(from: $0) }
                        ), in: 0...50, step: 0.5) {
                            Text(verbatim: "\(Self.format(bar)) \(unit.symbol)")
                        }
                    }
                }
                Section {
                    BarDiagram(plates: solution.best.platesPerSide)
                        .frame(height: 120)
                        .accessibilityHidden(true)
                    result
                } header: {
                    Text("plates.perSide")
                }
                alternatives
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background)
            .navigationTitle("plates.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("workout.ok") { dismiss() } } }
        }
        .accessibilityIdentifier("plate-calculator")
    }

    @ViewBuilder private var result: some View {
        let best = solution.best
        if solution.isBelowBar {
            Text("plates.below").foregroundStyle(DSColor.warning)
        } else if solution.isExact {
            Label("plates.exact", systemImage: "checkmark.circle.fill").foregroundStyle(DSColor.success)
        }
        if best.platesPerSide.isEmpty {
            Text("plates.empty").foregroundStyle(DSColor.textSecondary)
        } else {
            Text(verbatim: Self.summary(best.platesPerSide)).font(DSFont.headline).monospacedDigit()
                .accessibilityIdentifier("plates-summary")
        }
        LabeledContent("plates.total") { Text(verbatim: "\(Self.format(best.total)) \(unit.symbol)").monospacedDigit() }
    }

    @ViewBuilder private var alternatives: some View {
        if !solution.isExact {
            Section("plates.closest") {
                option("plates.lower", solution.lower)
                if let upper = solution.upper { option("plates.upper", upper) } else {
                    Text("plates.unreachable").foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        if let onApply {
            Section {
                Button("plates.apply") {
                    onApply(solution.best.total)
                    dismiss()
                }
                .accessibilityIdentifier("plates-apply")
            }
        }
    }

    private func option(_ title: LocalizedStringKey, _ load: PlateLoad) -> some View {
        Button { target = load.total } label: {
            HStack {
                Text(title)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(verbatim: "\(Self.format(load.total)) \(unit.symbol)").monospacedDigit()
                    Text(verbatim: load.platesPerSide.isEmpty ? "—" : Self.summary(load.platesPerSide))
                        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ type: BarType) -> String {
        let name = switch type {
        case .olympic20: String(localized: "plates.bar.olympic20")
        case .olympic15: String(localized: "plates.bar.olympic15")
        case .ez: String(localized: "plates.bar.ez")
        case .custom: String(localized: "plates.bar.custom")
        }
        guard let weight = type.weight(in: plateUnit) else { return name }
        return "\(name) · \(Self.format(weight)) \(unit.symbol)"
    }

    static func summary(_ plates: [Double]) -> String { plates.map(format).joined(separator: " + ") }

    static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

/// One half-bar drawing mirrored around the middle: plate height grows with weight.
private struct BarDiagram: View {
    let plates: [Double]

    var body: some View {
        let maxPlate = max(plates.max() ?? 1, 1)
        HStack(spacing: 2) {
            side(Array(plates.reversed()), maxPlate: maxPlate)
            Capsule().fill(DSColor.textTertiary).frame(width: 36, height: 8)
            side(plates, maxPlate: maxPlate)
        }
        .frame(maxWidth: .infinity)
    }

    private func side(_ list: [Double], maxPlate: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, weight in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DSColor.accent.opacity(0.45 + 0.55 * weight / maxPlate))
                    .frame(width: 12, height: 36 + 76 * weight / maxPlate)
            }
        }
    }
}
