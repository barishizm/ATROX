import DataKit
import DesignSystem
import SwiftUI

/// Calories left in the middle of a ring that fills as the day's calories add up.
struct CalorieRing: View {
    let consumed: Double
    let target: Int?

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return consumed / Double(target)
    }

    var body: some View {
        ZStack {
            Circle().stroke(DSColor.separator, lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(progress > 1 ? DSColor.warning : DSColor.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            VStack(spacing: Spacing.xxs) {
                if let target {
                    let left = Int((Double(target) - consumed).rounded())
                    Text(verbatim: "\(abs(left))").font(DSFont.numericLarge).foregroundStyle(DSColor.textPrimary)
                    Text(left >= 0 ? "nutrition.ring.left" : "nutrition.ring.over").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                } else {
                    Text(verbatim: "\(Int(consumed.rounded()))").font(DSFont.numericLarge).foregroundStyle(DSColor.textPrimary)
                    Text("nutrition.ring.eaten").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("nutrition.ring.a11y"))
        .accessibilityValue(Text(verbatim: target.map { "\(Int(consumed.rounded())) / \($0) kcal" } ?? "\(Int(consumed.rounded())) kcal"))
    }
}

/// One macro: name, grams eaten against the target, and a thin bar.
struct MacroBar: View {
    let title: LocalizedStringKey
    let grams: Double
    let target: Int?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            Text(verbatim: target.map { "\(Int(grams.rounded())) / \($0) g" } ?? "\(Int(grams.rounded())) g")
                .font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColor.separator)
                    Capsule().fill(tint).frame(width: proxy.size.width * min(fraction, 1))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double {
        guard let target, target > 0 else { return 0 }
        return grams / Double(target)
    }
}

extension MealType {
    var titleKey: LocalizedStringKey {
        switch self {
        case .breakfast: "nutrition.meal.breakfast"
        case .lunch: "nutrition.meal.lunch"
        case .dinner: "nutrition.meal.dinner"
        case .snack: "nutrition.meal.snack"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "carrot"
        }
    }
}

extension FoodSource {
    var systemImage: String {
        switch self {
        case .photo: "camera"
        case .text: "text.bubble"
        case .barcode: "barcode"
        case .manual: "square.and.pencil"
        }
    }
}

/// A numeric text field for grams / calories: keeps what the user types, parsed by the caller.
struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var unit: String
    var maximum: Double = 20_000

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title).foregroundStyle(DSColor.textPrimary)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused)
                .frame(maxWidth: 90)
                .onChange(of: text) { _, new in
                    let parsed = Double(new.replacingOccurrences(of: ",", with: ".")) ?? 0
                    value = min(max(parsed, 0), maximum)
                }
            Text(verbatim: unit).foregroundStyle(DSColor.textSecondary)
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, new in if !focused { text = Self.format(new) } }
        .frame(minHeight: HitTarget.minimum)
    }

    static func format(_ value: Double) -> String { value == 0 ? "" : (value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)) }
}
