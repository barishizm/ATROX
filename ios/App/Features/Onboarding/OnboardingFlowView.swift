import DataKit
import DesignSystem
import SwiftUI

/// Onboarding parts 1–3 (identity, training profile, consents): one question per screen, progress bar on top, back button, resumable.
struct OnboardingFlowView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: OnboardingViewModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                OnboardingContent(model: model)
            } else if unavailable {
                ErrorState(message: "onboarding.unavailable")
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .task {
            guard model == nil else { return }
            model = await container.makeOnboardingModel()
            unavailable = model == nil
        }
    }
}

private struct OnboardingContent: View {
    @Environment(AppContainer.self) private var container
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .trainingDone {
                header
            }
            ZStack {
                if model.isBlocked {
                    UnderAgeView { model.back() }
                } else {
                    page
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy, value: model.step)
            .animation(.snappy, value: model.isBlocked)
            if showsFooter {
                footer
            }
        }
        .background(DSColor.background)
        // The name field's keyboard would otherwise stay up over the following (non-text) steps.
        .onChange(of: model.step) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// The consent screens bring their own buttons.
    private var showsFooter: Bool {
        !model.isBlocked && ![.trainingDone, .terms, .contribution].contains(model.step)
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Button {
                model.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DSFont.headline)
                    .frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .opacity(model.canGoBack ? 1 : 0)
            .disabled(!model.canGoBack)
            .accessibilityLabel("onboarding.back")
            .accessibilityIdentifier("onboarding-back")

            ProgressBar(value: model.progress)
                .accessibilityElement()
                .accessibilityLabel("onboarding.progress")
                .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .name: NameStepView(model: model)
        case .birthDate: BirthDateStepView(model: model)
        case .sex: SexStepView(model: model)
        case .units: UnitsStepView(model: model)
        case .body: BodyStepView(model: model)
        case .experience: ExperienceStepView(model: model)
        case .goal: GoalStepView(model: model)
        case .frequency: FrequencyStepView(model: model)
        case .equipment: EquipmentStepView(model: model)
        case .limitations: LimitationsStepView(model: model)
        case .terms: TermsStepView(model: model)
        case .contribution: ContributionStepView(model: model)
        case .trainingDone: TrainingDoneView { container.root.didCompleteOnboarding() }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if model.saveFailed {
                Text("onboarding.saveError")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.error)
                    .accessibilityIdentifier("onboarding-save-error")
            }
            PrimaryButton("onboarding.continue", isLoading: model.isSaving) {
                Task { await model.advance() }
            }
            .disabled(!model.canAdvance)
            .accessibilityIdentifier("onboarding-continue")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
    }
}

/// Slim determinate bar in the accent color.
private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.surfaceRaised)
                Capsule().fill(DSColor.accent)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: value)
    }
}

/// Shared page layout: title, optional subtitle, content.
struct OnboardingPage<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(DSFont.title)
                        .foregroundStyle(DSColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                }
                content
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct TrainingDoneView: View {
    let finish: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)
            Text("onboarding.done.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text("onboarding.done.message")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            #if DEBUG
            // Temporary until P021 adds the last part; then onboarding completes after the last one.
            Button("onboarding.welcome.debugFinish", action: finish)
                .accessibilityIdentifier("onboarding-debug-finish")
            #endif
        }
        .padding(Spacing.lg)
        .accessibilityIdentifier("onboarding-training-done")
    }
}
