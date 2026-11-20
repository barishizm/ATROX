import DataKit
import DesignSystem
import SwiftUI

/// "Let's get tracking": progress toward the first three logged days.
struct NutritionTrackProgress: View {
    let trackedDays: Int
    private let goal = 3

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "sparkles").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("nutrition.track.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text("nutrition.track.subtitle").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<goal, id: \.self) { index in
                            Capsule().fill(index < trackedDays ? DSColor.accent : DSColor.separator).frame(height: 8)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nutrition-track")
    }
}

/// Eaten, the ring with what is left, burned, and the three macros.
struct NutritionSummaryCard: View {
    let model: NutritionModel
    let onTarget: () -> Void

    var body: some View {
        Card {
            VStack(spacing: Spacing.md) {
                HStack(alignment: .center) {
                    figure(Int(model.summary.calories.rounded()), "nutrition.summary.eaten")
                    CalorieRing(consumed: model.summary.calories, burned: model.burnedCalories, target: model.target?.values.calories)
                        .frame(maxWidth: .infinity)
                    figure(Int(model.burnedCalories.rounded()), "nutrition.summary.burned")
                }
                HStack(alignment: .top, spacing: Spacing.md) {
                    MacroBar(title: "nutrition.macro.carbs", grams: model.summary.carbsG, target: model.target?.values.carbsG, tint: DSColor.highlight)
                    MacroBar(title: "nutrition.macro.protein", grams: model.summary.proteinG, target: model.target?.values.proteinG, tint: DSColor.accent)
                    MacroBar(title: "nutrition.macro.fat", grams: model.summary.fatG, target: model.target?.values.fatG, tint: DSColor.success)
                }
                targetControl
            }
        }
        .accessibilityIdentifier("nutrition-summary")
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
                SecondaryButton("nutrition.target.set", systemImage: "target", action: onTarget)
                    .accessibilityIdentifier("nutrition-target-set")
            }
        }
    }
}
