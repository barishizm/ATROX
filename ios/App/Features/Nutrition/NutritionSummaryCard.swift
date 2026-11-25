import DataKit
import DesignSystem
import SwiftUI

/// Eaten, the ring with what is left, and the three macros.
struct NutritionSummaryCard: View {
    let model: NutritionModel
    let onTarget: () -> Void
    /// Drawn inside a card owned by the caller (shared with the meals) instead of in a card of its own.
    var embedded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if embedded {
            content.padding(Spacing.md).accessibilityIdentifier("nutrition-summary")
        } else {
            Card { content }.accessibilityIdentifier("nutrition-summary")
        }
    }

    private var content: some View {
            VStack(spacing: Spacing.md) {
                if typeSize.isAccessibilitySize {
                    ring
                    figure(Int(model.summary.calories.rounded()), "nutrition.summary.eaten")
                    VStack(alignment: .leading, spacing: Spacing.sm) { macros }
                } else {
                    HStack(alignment: .center) {
                        figure(Int(model.summary.calories.rounded()), "nutrition.summary.eaten")
                        ring.frame(maxWidth: .infinity)
                        // Same width as the figure, so the ring stays centred.
                        Color.clear.frame(width: 56, height: 1).accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: Spacing.md) { macros }
                }
                targetControl
            }
    }

    private var ring: some View {
        CalorieRing(consumed: model.summary.calories, target: model.target?.values.calories)
    }

    @ViewBuilder
    private var macros: some View {
        MacroBar(title: "nutrition.macro.carbs", grams: model.summary.carbsG, target: model.target?.values.carbsG, tint: DSColor.highlight)
        MacroBar(title: "nutrition.macro.protein", grams: model.summary.proteinG, target: model.target?.values.proteinG, tint: DSColor.accent)
        MacroBar(title: "nutrition.macro.fat", grams: model.summary.fatG, target: model.target?.values.fatG, tint: DSColor.success)
    }

    private func figure(_ value: Int, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(verbatim: "\(value)").font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
            Text(title).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        }
        .frame(minWidth: 56)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var targetControl: some View {
        if let target = model.target {
            Button(action: onTarget) {
                Label(
                    target.mode == .auto ? "nutrition.target.fromprofile" : "nutrition.target.fromyou",
                    systemImage: target.mode == .auto ? "wand.and.stars" : "slider.horizontal.3"
                )
                .font(DSFont.footnote)
            }
            .accessibilityIdentifier("nutrition-target-edit")
        } else {
            VStack(spacing: Spacing.xs) {
                Text("nutrition.target.missing").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
                SecondaryButton("nutrition.target.set", systemImage: "target") { onTarget() }
                    .accessibilityIdentifier("nutrition-target-set")
            }
        }
    }
}
