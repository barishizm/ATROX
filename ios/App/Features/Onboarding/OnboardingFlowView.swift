import DataKit
import DesignSystem
import SwiftUI

/// Onboarding parts 1–4 (identity, training profile, consents, first strength profile): one question per screen, progress bar on top, back button, resumable.
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
            if model.step != .result, model.step != .lifts {
                header
            }
            ZStack {
                if model.isBlocked {
                    UnderAgeView(changeDate: { model.back() }, signOut: { Task { await container.signOut() } })
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
        .background { OnboardingBackdrop(step: model.step) }
        .dsGlassSurfaces()
        .environment(\.colorScheme, .dark)
        // The name field's keyboard would otherwise stay up over the following (non-text) steps.
        .onAppear(perform: finishIfDone)
        .onChange(of: model.step) {
            finishIfDone()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// The flow ends right after the consents (the "first scores" screen is gone); sets can be logged later.
    private func finishIfDone() {
        guard model.step == .result else { return }
        model.finish()
        container.root.didCompleteOnboarding()
    }

    /// The consent screens bring their own buttons.
    private var showsFooter: Bool {
        !model.isBlocked && ![.lifts, .result, .terms, .contribution].contains(model.step)
    }

    /// Glass progress bar centered on the screen; the back button floats at the leading edge.
    private var header: some View {
        ZStack {
            GlassProgressBar(value: model.progress)
                .frame(width: 190)
                .accessibilityElement()
                .accessibilityLabel("onboarding.progress")
                .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
            HStack {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DSFont.headline)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .tint(dsGlassDim)
                .buttonBorderShape(.circle)
                .opacity(model.canGoBack ? 1 : 0)
                .disabled(!model.canGoBack)
                .accessibilityLabel("onboarding.back")
                .accessibilityIdentifier("onboarding-back")
                Spacer()
            }
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
        case .lifts: LiftsStepView(model: model)
        case .result: Color.clear  // Onboarding ends after the consents; see `onChange` below.
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

/// Determinate progress in a Liquid Glass capsule: a bright fill rides inside a glass track.
struct GlassProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [DSColor.accent, Color.white.opacity(0.95)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .padding(7)
        .glassEffect(Glass.regular.tint(dsGlassDim), in: Capsule())
        .animation(.snappy, value: value)
    }
}

/// Illustrated, blurred and darkened backdrop for the onboarding questions; it cross-fades between steps.
struct OnboardingBackdrop: View {
    /// Which of the illustrated backgrounds to show (0...5).
    let index: Int
    var extraDim: Double = 0
    private static let images = (1...6).map { "OnboardingBg\($0)" }

    init(index: Int, extraDim: Double = 0) {
        self.index = index
        self.extraDim = extraDim
    }

    init(step: OnboardingStep) {
        self.init(index: Self.index(for: step), extraDim: step == .terms || step == .contribution ? 0.3 : 0)
    }

    private static func index(for step: OnboardingStep) -> Int {
        switch step {
        case .name, .frequency: 0
        case .birthDate, .terms: 1
        case .sex, .limitations: 2
        case .units, .equipment: 3
        case .body, .goal: 4
        case .experience, .contribution: 5
        default: 0
        }
    }

    var body: some View {
        ZStack {
            DSColor.background
            ForEach(Self.images.indices, id: \.self) { position in
                Color.clear
                    .overlay {
                        Image(Self.images[position])
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 6)
                            .scaleEffect(1.05)
                    }
                    .clipped()
                    .opacity(position == index ? 1 : 0)
            }
            Color.black.opacity(extraDim)
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.4), Color.black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.6), value: index)
        .animation(.easeInOut(duration: 0.4), value: extraDim)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Slim determinate bar in the accent color.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.surfaceRaised)
                Capsule().fill(DSColor.accentFill)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: value)
    }
}

/// Shared page layout: title, optional subtitle, content. Centered both ways unless the step has a keyboard
/// (`centered: false`), where content stays at the top so the keyboard does not cover it.
struct OnboardingPage<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var centered = true
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: centered ? .center : .leading, spacing: Spacing.lg) {
                    VStack(alignment: centered ? .center : .leading, spacing: Spacing.sm) {
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
                .multilineTextAlignment(centered ? .center : .leading)
                .padding(Spacing.lg)
                .frame(maxWidth: 520, alignment: centered ? .center : .leading)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: centered ? .center : .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
