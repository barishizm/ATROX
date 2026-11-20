import DataKit
import DesignSystem
import SwiftUI

/// The four meals with what each has taken of its share of the day; "+" adds food to that meal.
struct NutritionMealsCard: View {
    let model: NutritionModel
    let onOpen: (MealType) -> Void
    let onAdd: (MealType) -> Void

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(MealType.allCases.enumerated()), id: \.element) { index, meal in
                    if index > 0 { Divider().overlay(DSColor.separator) }
                    row(meal)
                }
            }
        }
        .accessibilityIdentifier("nutrition-meals")
    }

    private func row(_ meal: MealType) -> some View {
        let eaten = Int(model.calories(for: meal).rounded())
        return HStack(spacing: Spacing.sm) {
            Button { onOpen(meal) } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: meal.systemImage).font(.title3).foregroundStyle(DSColor.accent)
                        .frame(width: 44, height: 44).background(DSColor.surfaceRaised, in: Circle()).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xxs) {
                            Text(meal.titleKey).font(DSFont.headline)
                            Image(systemName: "arrow.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                        }
                        .foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: model.mealBudgets?[meal].map { "\(eaten) / \($0) kcal" } ?? "\(eaten) kcal")
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nutrition-meal-\(meal.rawValue)")
            Button { onAdd(meal) } label: {
                Image(systemName: "plus").font(.title3.weight(.bold)).foregroundStyle(DSColor.onAccent)
                    .frame(width: 40, height: 40).background(DSColor.accentFill, in: Circle())
                    .frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .accessibilityLabel(Text("nutrition.add.more"))
            .accessibilityIdentifier("nutrition-add-\(meal.rawValue)")
        }
        .padding(Spacing.sm)
    }
}

/// One saved food; tap to edit, long-press for edit and delete.
struct FoodEntryRow: View {
    let entry: FoodEntrySnapshot
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let input = entry.input
        return Button(action: onEdit) {
            Card(padding: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    thumbnail(input)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(input.name).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                        MacroLine(protein: input.proteinG, carbs: input.carbsG, fat: input.fatG)
                            .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    Text(verbatim: "\(Int(input.calories.rounded()))").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                    Text("nutrition.unit.kcal").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onEdit) { Label("nutrition.entry.edit", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("nutrition.entry.delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("nutrition.entry.hint"))
    }

    @ViewBuilder
    private func thumbnail(_ input: FoodEntryInput) -> some View {
        if let data = input.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)).accessibilityHidden(true)
        } else {
            Image(systemName: input.source.systemImage).frame(width: 44, height: 44).foregroundStyle(DSColor.accent)
                .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)).accessibilityHidden(true)
        }
    }
}

/// Everything logged for one meal on the shown day.
struct MealDetailView: View {
    let model: NutritionModel
    let meal: MealType
    let onAdd: () -> Void
    let onEdit: (FoodEntrySnapshot) -> Void

    var body: some View {
        let entries = model.entries(for: meal)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if entries.isEmpty {
                    EmptyState(systemImage: meal.systemImage, title: "nutrition.empty.title", message: "nutrition.meal.empty")
                        .frame(minHeight: 260)
                }
                ForEach(entries) { entry in
                    FoodEntryRow(entry: entry, onEdit: { onEdit(entry) }, onDelete: { Task { await model.delete(id: entry.id) } })
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle(meal.titleKey)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onAdd) { Image(systemName: "plus") }.accessibilityLabel(Text("nutrition.add.more"))
            }
        }
        .accessibilityIdentifier("nutrition-meal-detail")
    }
}
