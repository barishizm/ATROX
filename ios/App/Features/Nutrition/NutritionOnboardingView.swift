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
        VStack(spacing: 0) {
            header
            page
                .id(flow.step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsContinue { footer }
        }
        .background { OnboardingBackdrop(index: backdropIndex) }
        .dsGlassSurfaces()
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("nutrition-quiz")
    }

    private var showsContinue: Bool { [.intro, .weight, .goalWeight, .plan].contains(flow.step) }

    /// The same illustrated backgrounds as the sign-up questions.
    private var backdropIndex: Int {
        switch flow.step {
        case .intro, .plan: 0
        case .weight, .goalWeight: 4
        case .pace, .diet: 3
        case .activity: 5
        case .cooking: 2
        case .time: 1
        }
    }

    private var footer: some View {
        PrimaryButton(
            flow.isLast ? "nutrition.quiz.plan.start" : "common.next", systemImage: flow.isLast ? "checkmark" : "arrow.right",
            isLoading: flow.saving
        ) {
            if flow.isLast { finish() } else { advance { flow.next() } }
        }
        .disabled(!flow.canContinue)
        .accessibilityIdentifier("quiz-continue")
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
    }

    private func advance(_ change: () -> Void) {
        withAnimation(.easeInOut(duration: 0.2)) { change() }
    }

    private func finish() {
        Task { if await flow.finish(on: model) { onClose() } }
    }

    /// Glass progress bar centered like the sign-up questions; back at the leading edge, skip at the trailing edge.
    private var header: some View {
        ZStack {
            GlassProgressBar(value: flow.progress)
                .frame(width: 190)
                .accessibilityElement()
                .accessibilityLabel("onboarding.progress")
                .accessibilityValue(Text(flow.progress, format: .percent.precision(.fractionLength(0))))
            HStack {
                Button { advance { flow.back() } } label: {
                    Image(systemName: "chevron.left").font(DSFont.headline).foregroundStyle(.white).frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .tint(dsGlassDim)
                .buttonBorderShape(.circle)
                .opacity(flow.index > 0 ? 1 : 0).disabled(flow.index == 0)
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
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    // MARK: Questions

    @ViewBuilder private var page: some View {
        switch flow.step {
        case .intro:
            OnboardingPage(title: "nutrition.quiz.intro.title") { intro }
        case .weight:
            OnboardingPage(title: "nutrition.quiz.weight.title", subtitle: "nutrition.quiz.weight.detail") {
                WeightWheel(value: $flow.weight, unit: flow.unit, title: "nutrition.weight.field")
            }
        case .goalWeight:
            OnboardingPage(title: "nutrition.quiz.goalweight.title") {
                WeightWheel(value: $flow.goalWeight, unit: flow.unit, title: "nutrition.weight.goal.field")
            }
        case .plan:
            OnboardingPage(title: "nutrition.quiz.plan.title", subtitle: "nutrition.quiz.plan.detail", centered: false) { plan }
        default:
            OnboardingPage(title: questionTitle) { choices }
        }
    }

    private var questionTitle: LocalizedStringKey {
        switch flow.step {
        case .pace: "nutrition.quiz.pace.title"
        case .activity: "nutrition.quiz.activity.title"
        case .cooking: "nutrition.quiz.cooking.title"
        case .time: "nutrition.quiz.time.title"
        default: "nutrition.quiz.diet.title"
        }
    }

    /// Explains why the questions start again: part 2 of sign-up, about food tracking.
    private var intro: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "fork.knife.circle.fill").font(.system(size: 44)).foregroundStyle(DSColor.accent).accessibilityHidden(true)
                Text("nutrition.quiz.intro.badge").font(DSFont.footnote.weight(.bold)).foregroundStyle(DSColor.accent)
                Text("nutrition.quiz.intro.detail").font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("quiz-intro")
    }

    private var choices: some View {
        VStack(spacing: Spacing.sm) { choiceList }
    }

    @ViewBuilder private var choiceList: some View {
        switch flow.step {
        case .pace:
            choice(flow.pace == .gentle, "tortoise", "nutrition.quiz.pace.gentle", "nutrition.quiz.pace.gentle.detail") { flow.pace = .gentle }
            choice(flow.pace == .steady, "figure.walk", "nutrition.quiz.pace.steady", "nutrition.quiz.pace.steady.detail") { flow.pace = .steady }
            choice(flow.pace == .fast, "hare", "nutrition.quiz.pace.fast", "nutrition.quiz.pace.fast.detail") { flow.pace = .fast }
        case .activity:
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
            choice(flow.cooking == .beginner, "frying.pan", "nutrition.quiz.cooking.beginner", "nutrition.quiz.cooking.beginner.detail") {
                flow.cooking = .beginner
            }
            choice(flow.cooking == .comfortable, "fork.knife", "nutrition.quiz.cooking.comfortable", "nutrition.quiz.cooking.comfortable.detail") {
                flow.cooking = .comfortable
            }
            choice(flow.cooking == .expert, "flame", "nutrition.quiz.cooking.expert", "nutrition.quiz.cooking.expert.detail") { flow.cooking = .expert }
        case .time:
            choice(flow.time == .quick, "timer", "nutrition.quiz.time.quick", nil) { flow.time = .quick }
            choice(flow.time == .medium, "clock", "nutrition.quiz.time.medium", nil) { flow.time = .medium }
            choice(flow.time == .relaxed, "hourglass", "nutrition.quiz.time.relaxed", nil) { flow.time = .relaxed }
        case .diet:
            choice(flow.diet == .anything, "takeoutbag.and.cup.and.straw", "nutrition.quiz.diet.anything", nil) { flow.diet = .anything }
            choice(flow.diet == .vegetarian, "carrot", "nutrition.quiz.diet.vegetarian", nil) { flow.diet = .vegetarian }
            choice(flow.diet == .vegan, "leaf", "nutrition.quiz.diet.vegan", nil) { flow.diet = .vegan }
        default:
            EmptyView()
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
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

/// Scroll wheel for a weight in the user's unit: half-kilo steps (metric) or whole pounds, like the sign-up body step.
private struct WeightWheel: View {
    @Binding var value: Double
    let unit: WeightUnit
    let title: LocalizedStringKey

    private var metric: Bool { unit == .kilograms }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(title).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            wheel.pickerStyle(.wheel).frame(height: 180).clipped()
        }
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: 260)
        .dsGlassFill(cornerRadius: Radius.lg)
    }

    @ViewBuilder private var wheel: some View {
        if metric {
            Picker(title, selection: Binding(
                get: { min(max(Int((value * 2).rounded()), 60), 600) },
                set: { value = Double($0) / 2 }
            )) {
                ForEach(60...600, id: \.self) { half in
                    Text(WeightFormat.string(kilograms: Double(half) / 2, unit: .kilograms, locale: .current)).tag(half)
                }
            }
            .accessibilityIdentifier("quiz-weight-wheel")
        } else {
            Picker(title, selection: Binding(
                get: { min(max(Int(value.rounded()), 66), 660) },
                set: { value = Double($0) }
            )) {
                ForEach(66...660, id: \.self) { Text("\($0) lb").tag($0) }
            }
            .accessibilityIdentifier("quiz-weight-wheel")
        }
    }
}
