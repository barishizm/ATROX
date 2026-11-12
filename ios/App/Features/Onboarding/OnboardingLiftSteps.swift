import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

// MARK: 13 · Best sets

/// "Enter your best sets": one card per basic lift, each skippable.
struct LiftsStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.lifts.title", subtitle: "onboarding.lifts.subtitle") {
            VStack(spacing: Spacing.md) {
                ForEach(OnboardingLifts.order, id: \.self) { lift in
                    LiftCard(model: model, lift: lift)
                }
            }
            if model.liftImplement == .dumbbell {
                Text("onboarding.lifts.dumbbellHint")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        PrimaryButton(model.reportedSets.isEmpty ? "onboarding.lifts.skipAll" : "onboarding.lifts.seeScore") {
            Task { await model.advance() }
        }
        .accessibilityIdentifier("onboarding-lifts-continue")
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
        .background(DSColor.background)
    }
}

private struct LiftCard: View {
    @Bindable var model: OnboardingViewModel
    let lift: BasicLift
    @State private var weightText = ""

    private var entry: LiftEntry { model.entry(for: lift) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(LiftNames.title(lift, implement: model.liftImplement))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                if entry.skipped {
                    Text("onboarding.lifts.skipped").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                } else {
                    inputs
                }
                Button(entry.skipped ? "onboarding.lifts.enter" : "onboarding.lifts.skip") {
                    model.setLiftSkipped(lift, !entry.skipped)
                }
                .font(DSFont.callout)
                .frame(minHeight: HitTarget.minimum)
                .accessibilityIdentifier("onboarding-lift-skip-\(lift.rawValue)")
            }
        }
        .onAppear { weightText = Self.text(model.entry(for: lift), unit: model.weightUnit) }
    }

    private var inputs: some View {
        HStack(alignment: .bottom, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.liftImplement == .dumbbell ? "onboarding.lifts.weightEach" : "onboarding.lifts.weight")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: HitTarget.button)
                    .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .trailing) {
                        Text(verbatim: model.weightUnit.symbol)
                            .font(DSFont.footnote)
                            .foregroundStyle(DSColor.textTertiary)
                            .padding(.trailing, Spacing.md)
                    }
                    .accessibilityLabel(Text("onboarding.lifts.weight"))
                    .accessibilityIdentifier("onboarding-lift-weight-\(lift.rawValue)")
                    .onChange(of: weightText) {
                        model.setLiftWeight(lift, value: Self.parse(weightText))
                    }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("onboarding.lifts.reps").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                Stepper(
                    value: Binding(get: { entry.reps ?? OnboardingLifts.defaultReps }, set: { model.setLiftReps(lift, reps: $0) }),
                    in: OnboardingLifts.repsRange
                ) {
                    Text(verbatim: "\(entry.reps ?? OnboardingLifts.defaultReps)")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .monospacedDigit()
                }
                .accessibilityLabel(Text("onboarding.lifts.reps"))
                .accessibilityIdentifier("onboarding-lift-reps-\(lift.rawValue)")
            }
        }
    }

    /// Accepts "82,5" and "82.5".
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func text(_ entry: LiftEntry, unit: WeightUnit) -> String {
        guard let kg = entry.weightKg else { return "" }
        let value = (unit.value(fromKilograms: kg) * 10).rounded() / 10
        return value == value.rounded() ? String(Int(value)) : String(value)
    }
}

enum LiftNames {
    static func title(_ lift: BasicLift, implement: LiftImplement) -> LocalizedStringKey {
        LocalizedStringKey("onboarding.lift.\(lift.rawValue).\(implement.rawValue)")
    }

    static func shortName(_ lift: BasicLift) -> LocalizedStringKey {
        LocalizedStringKey("onboarding.lift.\(lift.rawValue)")
    }
}

// MARK: 14 · First scores

struct ResultStepView: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.locale) private var locale
    let finish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if model.results.isEmpty {
                    empty
                } else {
                    scores
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { footer }
        .accessibilityIdentifier("onboarding-result")
    }

    private var scores: some View {
        VStack(spacing: Spacing.lg) {
            Text("onboarding.result.title")
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.results) { result in
                Card {
                    HStack(spacing: Spacing.lg) {
                        ScoreRing(score: result.score, diameter: 96, lineWidth: 10, showsLevel: false)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(LiftNames.shortName(result.lift)).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                            Text(LiftComments.comment(for: result.score))
                                .font(DSFont.callout)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding-result-\(result.lift.rawValue)")
            }
            templateSuggestions
            Text("onboarding.result.disclaimer")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding-result-disclaimer")
        }
    }

    /// The two program templates that fit the answers given so far (P034); they are picked under Workout → Programs.
    @ViewBuilder
    private var templateSuggestions: some View {
        let picks = model.recommendedTemplates
        if !picks.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("onboarding.result.templates.title")
                        .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    ForEach(picks, id: \.id) { template in
                        HStack {
                            Text(verbatim: template.name.resolve(languageCode: languageCode))
                                .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                            Spacer(minLength: Spacing.sm)
                            Text("template.summary \(template.daysPerWeek) \(template.estimatedMinutes)")
                                .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    Text("onboarding.result.templates.hint")
                        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
            }
            .accessibilityIdentifier("onboarding-result-templates")
        }
    }

    private var languageCode: String { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }

    private var empty: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: Spacing.xl)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text("onboarding.result.empty.title")
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("onboarding.result.empty.message")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("onboarding-result-empty")
    }

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            PrimaryButton("onboarding.result.start") {
                model.finish()
                finish()
            }
            .accessibilityIdentifier("onboarding-finish")
            SecondaryButton("onboarding.result.edit") { model.back() }
                .accessibilityIdentifier("onboarding-result-edit")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
        .background(DSColor.background)
    }
}

/// One sentence per score band. TEMPORARY wording until the real model (P061–P062).
enum LiftComments {
    static func comment(for score: Double) -> LocalizedStringKey {
        switch ScoreLevel(score: score) {
        case .beginner: "onboarding.result.comment.beginner"
        case .developing: "onboarding.result.comment.developing"
        case .intermediate: "onboarding.result.comment.intermediate"
        case .advanced: "onboarding.result.comment.advanced"
        case .expert, .elite: "onboarding.result.comment.expert"
        }
    }
}
