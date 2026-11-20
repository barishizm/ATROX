import DataKit
import DesignSystem
import SwiftUI

/// The first-run quiz of the Calories tab; ends with an editable daily plan.
struct NutritionOnboardingView: View {
    let model: NutritionModel
    let onClose: () -> Void
    @State private var flow: NutritionOnboardingModel

    init(model: NutritionModel, profile: NutritionProfile, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _flow = State(initialValue: NutritionOnboardingModel(profile: profile, preferences: NutritionPreferences.load(userId: model.userId)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) { question }
                    .padding(.bottom, Spacing.lg)
                    .id(flow.step)
                    .transition(.opacity)
            }
            .scrollDismissesKeyboard(.interactively)
            if showsContinue {
                PrimaryButton(
                    flow.isLast ? "nutrition.quiz.plan.start" : "common.next", systemImage: flow.isLast ? "checkmark" : "arrow.right",
                    isLoading: flow.saving
                ) {
                    if flow.isLast { finish() } else { advance { flow.next() } }
                }
                .disabled(!flow.canContinue)
                .accessibilityIdentifier("quiz-continue")
            }
        }
        .padding(Spacing.md)
        .dsGlassSurfaces()
        .background(NutritionBackdrop().ignoresSafeArea())
        .interactiveDismissDisabled()
        .accessibilityIdentifier("nutrition-quiz")
    }

    private var showsContinue: Bool { [.weight, .goalWeight, .plan].contains(flow.step) }

    private func advance(_ change: () -> Void) {
        withAnimation(.easeInOut(duration: 0.2)) { change() }
    }

    private func finish() {
        Task { if await flow.finish(on: model) { onClose() } }
    }

    private var topBar: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Button { advance { flow.back() } } label: { Image(systemName: "chevron.backward").font(.title3.weight(.semibold)) }
                    .opacity(flow.index > 0 ? 1 : 0).disabled(flow.index == 0)
                    .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                    .accessibilityLabel(Text("common.back"))
                Spacer()
                Button("nutrition.quiz.skip") {
                    NutritionPreferences.markQuizFinished(userId: model.userId)
                    onClose()
                }
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                .frame(minHeight: HitTarget.minimum)
                .accessibilityIdentifier("quiz-skip")
            }
            ProgressView(value: flow.progress).tint(DSColor.accent)
        }
    }

    // MARK: Questions

    @ViewBuilder
    private var question: some View {
        switch flow.step {
        case .goal:
            title("nutrition.quiz.goal.title")
            choice(flow.goal == .fatLoss, "arrow.down.right.circle", "nutrition.quiz.goal.lose", "nutrition.quiz.goal.lose.detail") { flow.goal = .fatLoss }
            choice([.generalHealth, .strength].contains(flow.goal), "heart", "nutrition.quiz.goal.maintain", "nutrition.quiz.goal.maintain.detail") {
                flow.goal = .generalHealth
            }
            choice(flow.goal == .muscleGain, "arrow.up.right.circle", "nutrition.quiz.goal.gain", "nutrition.quiz.goal.gain.detail") {
                flow.goal = .muscleGain
            }
        case .weight:
            title("nutrition.quiz.weight.title", detail: "nutrition.quiz.weight.detail")
            Card { NumberField(title: "nutrition.weight.field", value: $flow.weight, unit: flow.unit.symbol, maximum: 900) }
        case .goalWeight:
            title("nutrition.quiz.goalweight.title")
            Card { NumberField(title: "nutrition.weight.goal.field", value: $flow.goalWeight, unit: flow.unit.symbol, maximum: 900) }
        case .pace:
            title("nutrition.quiz.pace.title")
            choice(flow.pace == .gentle, "tortoise", "nutrition.quiz.pace.gentle", "nutrition.quiz.pace.gentle.detail") { flow.pace = .gentle }
            choice(flow.pace == .steady, "figure.walk", "nutrition.quiz.pace.steady", "nutrition.quiz.pace.steady.detail") { flow.pace = .steady }
            choice(flow.pace == .fast, "hare", "nutrition.quiz.pace.fast", "nutrition.quiz.pace.fast.detail") { flow.pace = .fast }
        case .activity:
            title("nutrition.quiz.activity.title")
            choice(flow.activity == .sedentary, "chair.lounge", "nutrition.quiz.activity.sedentary", "nutrition.quiz.activity.sedentary.detail") {
                flow.activity = .sedentary
            }
            choice(flow.activity == .light, "figure.walk", "nutrition.quiz.activity.light", "nutrition.quiz.activity.light.detail") { flow.activity = .light }
            choice(flow.activity == .moderate, "figure.stand", "nutrition.quiz.activity.moderate", "nutrition.quiz.activity.moderate.detail") {
                flow.activity = .moderate
            }
            choice(flow.activity == .active, "figure.run", "nutrition.quiz.activity.active", "nutrition.quiz.activity.active.detail") {
                flow.activity = .active
            }
        case .cooking:
            title("nutrition.quiz.cooking.title")
            choice(flow.cooking == .beginner, "frying.pan", "nutrition.quiz.cooking.beginner", "nutrition.quiz.cooking.beginner.detail") {
                flow.cooking = .beginner
            }
            choice(flow.cooking == .comfortable, "fork.knife", "nutrition.quiz.cooking.comfortable", "nutrition.quiz.cooking.comfortable.detail") {
                flow.cooking = .comfortable
            }
            choice(flow.cooking == .expert, "flame", "nutrition.quiz.cooking.expert", "nutrition.quiz.cooking.expert.detail") { flow.cooking = .expert }
        case .time:
            title("nutrition.quiz.time.title")
            choice(flow.time == .quick, "timer", "nutrition.quiz.time.quick", nil) { flow.time = .quick }
            choice(flow.time == .medium, "clock", "nutrition.quiz.time.medium", nil) { flow.time = .medium }
            choice(flow.time == .relaxed, "hourglass", "nutrition.quiz.time.relaxed", nil) { flow.time = .relaxed }
        case .diet:
            title("nutrition.quiz.diet.title")
            choice(flow.diet == .anything, "takeoutbag.and.cup.and.straw", "nutrition.quiz.diet.anything", nil) { flow.diet = .anything }
            choice(flow.diet == .vegetarian, "carrot", "nutrition.quiz.diet.vegetarian", nil) { flow.diet = .vegetarian }
            choice(flow.diet == .vegan, "leaf", "nutrition.quiz.diet.vegan", nil) { flow.diet = .vegan }
        case .plan:
            plan
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            title("nutrition.quiz.plan.title", detail: "nutrition.quiz.plan.detail")
            Card {
                VStack {
                    NumberField(title: "nutrition.manual.calories", value: $flow.calories, unit: "kcal", maximum: 10_000)
                    NumberField(title: "nutrition.macro.protein", value: $flow.protein, unit: "g", maximum: 1000)
                    NumberField(title: "nutrition.macro.carbs", value: $flow.carbs, unit: "g", maximum: 2000)
                    NumberField(title: "nutrition.macro.fat", value: $flow.fat, unit: "g", maximum: 1000)
                }
            }
            if flow.edited != flow.suggestion {
                SecondaryButton("nutrition.target.suggest", systemImage: "wand.and.stars") { flow.applySuggestion() }
            }
            Text("nutrition.quiz.plan.note").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            if flow.failed { Text("nutrition.save.failed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
        }
    }

    private func title(_ key: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(key).font(DSFont.title).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
        }
    }

    private func choice(
        _ selected: Bool, _ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey?, apply: @escaping () -> Void
    ) -> some View {
        Button { advance { flow.choose(apply) } } label: {
            Card {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon).font(.title2).foregroundStyle(DSColor.accent).frame(width: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        if let detail { Text(detail).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.leading) }
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? DSColor.accent : DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
