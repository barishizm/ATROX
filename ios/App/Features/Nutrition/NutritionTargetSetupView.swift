import DataKit
import DesignSystem
import SwiftUI

/// Where the daily target comes from: calculated from the profile, or entered by the user step by step.
struct NutritionTargetSetupView: View {
    let profile: NutritionProfile?
    let current: NutritionTargetInput?
    let onSave: (NutritionTargetInput) async -> Bool
    let onClose: () -> Void

    private enum Step { case choose, auto, manualCalories, manualMacros }

    @State private var step: Step = .choose
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var saving = false
    @State private var failed = false

    init(
        profile: NutritionProfile?, current: NutritionTargetInput?, onSave: @escaping (NutritionTargetInput) async -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.current = current
        self.onSave = onSave
        self.onClose = onClose
        let seed = current?.values ?? profile?.autoTarget
        _calories = State(initialValue: Double(seed?.calories ?? 0))
        _protein = State(initialValue: Double(seed?.proteinG ?? 0))
        _carbs = State(initialValue: Double(seed?.carbsG ?? 0))
        _fat = State(initialValue: Double(seed?.fatG ?? 0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    switch step {
                    case .choose: choose
                    case .auto: auto
                    case .manualCalories: manualCalories
                    case .manualMacros: manualMacros
                    }
                }
                .padding(Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("nutrition.target.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel", action: onClose) }
                if step != .choose {
                    ToolbarItem(placement: .navigation) {
                        Button { back() } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(Text("common.back"))
                    }
                }
            }
        }
        .accessibilityIdentifier("target-setup")
    }

    private func back() {
        switch step {
        case .manualMacros: step = .manualCalories
        default: step = .choose
        }
    }

    // MARK: Steps

    private var choose: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("nutrition.target.intro").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
            option(icon: "wand.and.stars", title: "nutrition.target.auto.title", detail: "nutrition.target.auto.detail", id: "target-auto") { step = .auto }
            option(icon: "slider.horizontal.3", title: "nutrition.target.manual.title", detail: "nutrition.target.manual.detail", id: "target-manual") {
                prefillManualIfEmpty()
                step = .manualCalories
            }
        }
    }

    private func option(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon).font(.title2).foregroundStyle(DSColor.accent).frame(width: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        Text(detail).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var auto: some View {
        if let values = profile?.autoTarget, let profile {
            Text("nutrition.target.auto.intro").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: "\(values.calories) kcal").font(DSFont.numericLarge).foregroundStyle(DSColor.textPrimary)
                    HStack {
                        stat("nutrition.macro.protein", values.proteinG)
                        stat("nutrition.macro.carbs", values.carbsG)
                        stat("nutrition.macro.fat", values.fatG)
                    }
                }
            }
            Label(goalKey(profile.goal), systemImage: "target").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            if profile.ageYears < 18 { Text("nutrition.target.minor").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary) }
            if failed { Text("nutrition.save.failed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
            PrimaryButton("nutrition.target.use", systemImage: "checkmark", isLoading: saving) {
                save(NutritionTargetInput(mode: .auto, values: values, activity: profile.activity))
            }
            .accessibilityIdentifier("target-use-auto")
        } else {
            EmptyState(
                systemImage: "scalemass",
                title: "nutrition.target.noweight.title",
                message: "nutrition.target.noweight.message",
                actionTitle: "nutrition.target.manual.title"
            ) {
                prefillManualIfEmpty()
                step = .manualCalories
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ grams: Int) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            Text(verbatim: "\(grams) g").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goalKey(_ goal: Goal) -> LocalizedStringKey {
        switch goal {
        case .strength: "nutrition.goal.strength"
        case .muscleGain: "nutrition.goal.muscleGain"
        case .fatLoss: "nutrition.goal.fatLoss"
        case .generalHealth: "nutrition.goal.generalHealth"
        }
    }

    private var manualCalories: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("nutrition.target.step1").font(DSFont.headline)
            Text("nutrition.target.step1.detail").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            Card { NumberField(title: "nutrition.manual.calories", value: $calories, unit: "kcal", maximum: 10_000) }
            if calories > 0 && calories < 1200 {
                Label("nutrition.target.low", systemImage: "exclamationmark.triangle").font(DSFont.footnote).foregroundStyle(DSColor.warning)
            }
            PrimaryButton("common.next", systemImage: "arrow.right") {
                if protein == 0 && carbs == 0 && fat == 0 { suggestMacros() }
                step = .manualMacros
            }
            .disabled(calories < 800)
            .accessibilityIdentifier("target-next")
        }
    }

    private var manualMacros: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("nutrition.target.step2").font(DSFont.headline)
            Text("nutrition.target.step2.detail").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            Card {
                VStack {
                    NumberField(title: "nutrition.macro.protein", value: $protein, unit: "g", maximum: 1000)
                    NumberField(title: "nutrition.macro.carbs", value: $carbs, unit: "g", maximum: 2000)
                    NumberField(title: "nutrition.macro.fat", value: $fat, unit: "g", maximum: 1000)
                }
            }
            let fromMacros = Int((protein * 4 + carbs * 4 + fat * 9).rounded())
            HStack(spacing: Spacing.xs) {
                Text(verbatim: "\(fromMacros) / \(Int(calories)) kcal")
                Text("nutrition.target.macrosum")
            }
            .font(DSFont.footnote).foregroundStyle(abs(Double(fromMacros) - calories) > calories * 0.1 ? DSColor.warning : DSColor.textSecondary)
            SecondaryButton("nutrition.target.suggest", systemImage: "wand.and.stars") { suggestMacros() }
            if failed { Text("nutrition.save.failed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
            PrimaryButton("nutrition.target.use", systemImage: "checkmark", isLoading: saving) {
                save(NutritionTargetInput(
                    mode: .manual, values: NutritionTargetValues(calories: Int(calories), proteinG: Int(protein), carbsG: Int(carbs), fatG: Int(fat)),
                    activity: profile?.activity ?? current?.activity ?? .moderate
                ))
            }
            .accessibilityIdentifier("target-use-manual")
        }
    }

    // MARK: Helpers

    private func prefillManualIfEmpty() {
        guard calories == 0, let values = profile?.autoTarget else { return }
        calories = Double(values.calories)
        protein = Double(values.proteinG)
        carbs = Double(values.carbsG)
        fat = Double(values.fatG)
    }

    /// 30 % protein-ish split guided by body weight when known, 25 % fat, the rest carbs.
    private func suggestMacros() {
        let weight = profile?.weightKg ?? 70
        protein = min((weight * 1.8).rounded(), calories * 0.4 / 4)
        fat = (calories * 0.25 / 9).rounded()
        carbs = max(0, ((calories - protein * 4 - fat * 9) / 4).rounded())
    }

    private func save(_ input: NutritionTargetInput) {
        saving = true
        failed = false
        Task {
            let saved = await onSave(input)
            saving = false
            if saved { onClose() } else { failed = true }
        }
    }
}
