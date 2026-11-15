import DataKit
import DesignSystem
import SwiftUI

/// Pre-sign-up questions led by the mascot: progress bar on top, the question in the mascot's speech bubble,
/// a quiet explanation under it, the answer controls, and "Next". The last page is the "designing your plan"
/// animation; its "Next" goes on to creating the account.
struct PlanQuizView: View {
    let authModel: AuthFlowModel
    @State private var model = PlanQuizModel()
    @State private var planReady = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if model.isBlocked {
                        UnderAgeView { model.back() }
                            .frame(minHeight: 420)
                    } else {
                        page
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .id(model.step)
                .transition(.opacity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            if !model.isBlocked { footer }
        }
        .animation(.easeInOut(duration: 0.25), value: model.step)
        .background(DSColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.step) { nameFocused = false }
        .accessibilityIdentifier("plan-quiz")
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Button {
                if model.canGoBack { model.back() } else { authModel.path.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(DSFont.headline)
                    .frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .accessibilityLabel("onboarding.back")
            .accessibilityIdentifier("quiz-back")

            ProgressBar(value: model.progress)
                .accessibilityElement()
                .accessibilityLabel("onboarding.progress")
                .accessibilityValue(Text(model.progress, format: .percent.precision(.fractionLength(0))))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            if model.step == .contribution {
                PrimaryButton("onboarding.contribution.accept") {
                    model.setContribution(true)
                    model.advance()
                }
                .accessibilityIdentifier("quiz-contribution-accept")
                Button {
                    model.setContribution(false)
                    model.advance()
                } label: {
                    Text("onboarding.contribution.skip")
                        .font(DSFont.callout.weight(.semibold))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                }
                .accessibilityIdentifier("quiz-contribution-skip")
            } else {
                PrimaryButton(model.step == .terms ? "onboarding.terms.accept" : "quiz.next") {
                    if model.step == .building {
                        authModel.path.append(.methods(.signUp))
                    } else {
                        model.advance()
                    }
                }
                .disabled(model.step == .building ? !planReady : !model.canAdvance)
                .accessibilityIdentifier("quiz-next")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch model.step {
        case .name:
            MascotSpeech(image: "MascotHappy", message: "quiz.name.question", mascotWidth: 96)
            note("quiz.name.why")
            nameField
        case .sex:
            MascotSpeech(image: "MascotCool", message: "quiz.sex.question \(model.answers.firstName)", mascotWidth: 140)
            note("quiz.sex.why")
            sexCards
        case .weight:
            MascotSpeech(image: "MascotHappy", message: "quiz.weight.question", mascotWidth: 140)
            note("quiz.weight.why")
            unitPicker
            weightWheel
        case .height:
            MascotSpeech(image: "MascotExcited", message: "quiz.height.question", mascotWidth: 140)
            unitPicker
            heightWheel
        case .birthDate:
            MascotSpeech(image: "MascotHappy", message: "quiz.birth.question", mascotWidth: 140)
            note("quiz.birth.why")
            birthDatePicker
        case .goals:
            MascotSpeech(image: "MascotExcited", message: "quiz.goals.question", mascotWidth: 140)
            note("quiz.goals.why")
            goalCards
        case .muscles:
            MascotSpeech(image: "MascotCool", message: "quiz.muscles.question", mascotWidth: 90)
            note("quiz.muscles.why")
            muscleCards
        case .experience:
            MascotSpeech(image: "MascotHappy", message: "quiz.experience.question", mascotWidth: 140)
            note("quiz.experience.why")
            experienceCards
        case .equipment:
            MascotSpeech(image: "MascotCool", message: "quiz.equipment.question", mascotWidth: 140)
            equipmentCards
        case .frequency:
            MascotSpeech(image: "MascotExcited", message: "quiz.frequency.question", mascotWidth: 140)
            frequencyPicker
        case .limitations:
            MascotSpeech(image: "MascotHappy", message: "quiz.limitations.question", mascotWidth: 90)
            note("quiz.limitations.why")
            limitationCards
        case .terms:
            MascotSpeech(image: "MascotCool", message: "quiz.terms.question", mascotWidth: 90)
            note("quiz.terms.why")
            termsLinks
        case .contribution:
            MascotSpeech(image: "MascotExcited", message: "quiz.contribution.question", mascotWidth: 90)
            note("quiz.contribution.why")
            contributionInfo
        case .building:
            BuildingPlanView(isFinished: $planReady)
        }
    }

    /// The quiet line under the question.
    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DSFont.footnote)
            .foregroundStyle(DSColor.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.sm)
    }

    // MARK: Name

    private var nameField: some View {
        TextField("quiz.name.placeholder", text: Binding(get: { model.firstName }, set: { model.firstName = $0 }))
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($nameFocused)
            .onSubmit { model.advance() }
            .font(DSFont.title)
            .multilineTextAlignment(.center)
            .padding(Spacing.md)
            .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .accessibilityIdentifier("quiz-name-field")
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                nameFocused = true
            }
    }

    // MARK: Sex

    private var sexCards: some View {
        VStack(spacing: Spacing.sm) {
            card("onboarding.sex.male", selected: model.answers.sex == .male, id: "quiz-sex-male") { model.setSex(.male) }
            card("onboarding.sex.female", selected: model.answers.sex == .female, id: "quiz-sex-female") { model.setSex(.female) }
            card("quiz.sex.nonbinary", selected: model.answers.sex == .unspecified, id: "quiz-sex-nonbinary") {
                model.setSex(.unspecified)
            }
        }
    }

    // MARK: Weight and height

    private var isMetric: Bool { model.answers.unitSystem == .metric }

    private var unitPicker: some View {
        Picker("quiz.unit", selection: Binding(get: { model.answers.unitSystem }, set: { model.setUnitSystem($0) })) {
            Text(verbatim: "kg · cm").tag(UnitSystem.metric)
            Text(verbatim: "lb · ft").tag(UnitSystem.imperial)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("quiz-units")
    }

    /// Metric: half-kilo steps (selection is the half-kilo count). Imperial: whole pounds.
    @ViewBuilder private var weightWheel: some View {
        Group {
            if isMetric {
                Picker("quiz.weight.question", selection: Binding(
                    get: { Int((model.answers.weightKg * 2).rounded()).clamped(to: 60...600) },
                    set: { model.setWeight(kg: Double($0) / 2) }
                )) {
                    ForEach(60...600, id: \.self) { half in
                        Text(WeightFormat.string(kilograms: Double(half) / 2, unit: .kilograms, locale: .current)).tag(half)
                    }
                }
            } else {
                Picker("quiz.weight.question", selection: Binding(
                    get: { Int(WeightUnit.pounds.value(fromKilograms: model.answers.weightKg).rounded()).clamped(to: 66...660) },
                    set: { model.setWeight(kg: WeightUnit.pounds.kilograms(from: Double($0))) }
                )) {
                    ForEach(66...660, id: \.self) { Text("\($0) lb").tag($0) }
                }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 200)
        .clipped()
        .accessibilityIdentifier("quiz-weight")
    }

    @ViewBuilder private var heightWheel: some View {
        Group {
            if isMetric {
                Picker("quiz.height.question", selection: Binding(
                    get: { Int(model.answers.heightCm.rounded()).clamped(to: 100...250) },
                    set: { model.setHeight(cm: Double($0)) }
                )) {
                    ForEach(100...250, id: \.self) { Text("\($0) cm").tag($0) }
                }
            } else {
                Picker("quiz.height.question", selection: Binding(
                    get: { Int(LengthFormat.inches(fromCentimeters: model.answers.heightCm).rounded()).clamped(to: 40...98) },
                    set: { model.setHeight(cm: LengthFormat.centimeters(feet: $0 / 12, inches: $0 % 12)) }
                )) {
                    ForEach(40...98, id: \.self) { Text("\($0 / 12)′ \($0 % 12)″").tag($0) }
                }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 200)
        .clipped()
        .accessibilityIdentifier("quiz-height")
    }

    // MARK: Birth date

    private var birthDatePicker: some View {
        DatePicker(
            "quiz.birth.question",
            selection: Binding(get: { model.birthDateForDisplay }, set: { model.setBirthDate($0) }),
            in: model.birthDateRange,
            displayedComponents: .date
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("quiz-birth-date")
    }

    // MARK: Goals, muscles

    private var goalCards: some View {
        let options: [(Goal, String, String)] = [
            (.strength, "onboarding.goal.strength", "bolt.fill"),
            (.muscleGain, "onboarding.goal.muscle", "figure.strengthtraining.traditional"),
            (.fatLoss, "onboarding.goal.fat", "flame.fill"),
            (.generalHealth, "onboarding.goal.health", "heart.fill"),
        ]
        return VStack(spacing: Spacing.sm) {
            ForEach(options, id: \.0) { goal, key, icon in
                let selected = model.answers.goals.contains(goal)
                SelectableCard(
                    LocalizedStringKey(key), subtitle: LocalizedStringKey(key + ".detail"), systemImage: icon,
                    isSelected: selected, indicator: .checkbox
                ) { model.toggleGoal(goal) }
                    .opacity(selected || model.canPickMoreGoals ? 1 : 0.4)
                    .accessibilityIdentifier("quiz-goal-\(goal.rawValue)")
            }
        }
    }

    private var muscleCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible())], spacing: Spacing.sm) {
            ForEach(FocusMuscle.allCases, id: \.self) { muscle in
                MuscleRegionCard(
                    muscle: muscle, isSelected: model.answers.focusMuscles.contains(muscle)
                ) { model.toggleMuscle(muscle) }
                    .accessibilityIdentifier("quiz-muscle-\(muscle.rawValue)")
            }
        }
    }

    // MARK: Level, equipment

    private var experienceCards: some View {
        let options: [(Experience, String)] = [
            (.noExperience, "onboarding.experience.none"),
            (.under6Months, "onboarding.experience.under6"),
            (.sixMonthsToTwoYears, "onboarding.experience.6to24"),
            (.twoToFiveYears, "onboarding.experience.2to5"),
            (.over5Years, "onboarding.experience.over5"),
        ]
        return VStack(spacing: Spacing.sm) {
            ForEach(options, id: \.0) { value, key in
                SelectableCard(
                    LocalizedStringKey(key), subtitle: LocalizedStringKey(key + ".detail"),
                    isSelected: model.answers.experience == value
                ) { model.setExperience(value) }
                    .accessibilityIdentifier("quiz-experience-\(value.rawValue)")
            }
        }
    }

    private var equipmentCards: some View {
        let options: [(EquipmentAccess, String, String)] = [
            (.fullGym, "onboarding.equipment.gym", "building.2.fill"),
            (.homeBarbell, "onboarding.equipment.homeBarbell", "house.fill"),
            (.homeDumbbell, "onboarding.equipment.homeDumbbell", "dumbbell.fill"),
            (.bodyweightOnly, "onboarding.equipment.bodyweight", "figure.core.training"),
        ]
        return VStack(spacing: Spacing.sm) {
            ForEach(options, id: \.0) { value, key, icon in
                SelectableCard(
                    LocalizedStringKey(key), subtitle: LocalizedStringKey(key + ".detail"), systemImage: icon,
                    isSelected: model.answers.equipment == value
                ) { model.setEquipment(value) }
                    .accessibilityIdentifier("quiz-equipment-\(value.rawValue)")
            }
        }
    }

    // MARK: Days per week

    private var frequencyPicker: some View {
        VStack(spacing: Spacing.lg) {
            Text("onboarding.frequency.days \(model.answers.weeklyFrequency)")
                .font(DSFont.display)
                .foregroundStyle(DSColor.accent)
                .frame(maxWidth: .infinity)
            HStack(spacing: Spacing.xs) {
                ForEach(OnboardingRules.weeklyFrequencyRange, id: \.self) { day in
                    let selected = model.answers.weeklyFrequency == day
                    Button {
                        Haptics.play(.selection)
                        model.setWeeklyFrequency(day)
                    } label: {
                        Text("\(day)")
                            .font(DSFont.headline)
                            .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                            .background(
                                selected ? DSColor.accentFill : DSColor.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("onboarding.frequency.days \(day)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("quiz-frequency-\(day)")
                }
            }
        }
    }

    // MARK: Areas to protect

    private var limitationCards: some View {
        let titles: [(BodyLimitation, String)] = [
            (.shoulder, "onboarding.limits.shoulder"), (.lowerBack, "onboarding.limits.lowerBack"),
            (.knee, "onboarding.limits.knee"), (.elbow, "onboarding.limits.elbow"),
            (.wrist, "onboarding.limits.wrist"), (.hip, "onboarding.limits.hip"),
        ]
        return VStack(spacing: Spacing.sm) {
            ForEach(titles, id: \.0) { area, key in
                SelectableCard(
                    LocalizedStringKey(key), isSelected: model.answers.limitations.contains(area), indicator: .checkbox
                ) { model.toggleLimitation(area) }
                    .accessibilityIdentifier("quiz-limits-\(area.rawValue)")
            }
            SelectableCard("onboarding.limits.none", isSelected: model.answers.noLimitations, indicator: .checkbox) {
                model.toggleNoLimitations()
            }
            .accessibilityIdentifier("quiz-limits-none")
        }
    }

    // MARK: Model contribution

    private var contributionInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                assurance("person.crop.circle.badge.xmark", "onboarding.contribution.assure.identity")
                assurance("chart.bar.xaxis", "onboarding.contribution.assure.data")
                assurance("switch.2", "onboarding.contribution.assure.anytime")
            }
            ContributionDetailsView()
        }
    }

    private func assurance(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: systemImage).frame(width: 28).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text(text).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
        }
    }

    // MARK: Terms

    private var termsLinks: some View {
        let legal = LegalLinks.current
        return VStack(alignment: .leading, spacing: Spacing.md) {
            termsRow("onboarding.terms.termsLink", systemImage: "doc.text", url: legal.terms, id: "quiz-terms-link")
            termsRow("onboarding.terms.privacyLink", systemImage: "lock.shield", url: legal.privacy, id: "quiz-privacy-link")
            Text("onboarding.terms.age")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    @ViewBuilder
    private func termsRow(_ title: LocalizedStringKey, systemImage: String, url: URL?, id: String) -> some View {
        let label = HStack(spacing: Spacing.md) {
            Image(systemName: systemImage).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            if url != nil {
                Image(systemName: "arrow.up.right").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        Card {
            if let url {
                Link(destination: url) { label.frame(minHeight: HitTarget.minimum) }.accessibilityIdentifier(id)
            } else {
                label.frame(minHeight: HitTarget.minimum)
            }
        }
    }

    // MARK: Helpers

    private func card(_ title: LocalizedStringKey, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        SelectableCard(title, isSelected: selected, action: action).accessibilityIdentifier(id)
    }
}

private extension FocusMuscle {
    /// How far the body diagram is zoomed in the card, and which point of it stays in view.
    var zoom: CGFloat {
        switch self {
        case .chest: 2.6
        case .legs: 2.0
        case .arms: 2.4
        case .abs: 3.0
        }
    }

    var zoomAnchor: UnitPoint {
        switch self {
        case .chest: UnitPoint(x: 0.5, y: 0.20)
        case .legs: UnitPoint(x: 0.5, y: 0.78)
        case .arms: UnitPoint(x: 0.5, y: 0.32)
        case .abs: UnitPoint(x: 0.5, y: 0.34)
        }
    }
}

/// One body region: the body diagram with the region lit, its name and a checkbox.
private struct MuscleRegionCard: View {
    let muscle: FocusMuscle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            VStack(spacing: Spacing.sm) {
                // The diagram sits on a darker plate (unlit muscles would vanish into the card) and is zoomed
                // onto the region so it reads at a glance.
                MuscleMapView(
                    primary: muscle.catalogMuscles,
                    style: MuscleMapStyle(side: .front, showsOutline: true, highlight: DSColor.highlightFill)
                )
                .frame(height: 112)
                .scaleEffect(muscle.zoom, anchor: muscle.zoomAnchor)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipped()
                .background(DSColor.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                HStack {
                    Text(LocalizedStringKey("quiz.muscle." + muscle.rawValue))
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

// MARK: - "ATROX is designing your plan"

/// A short, purely decorative animation: a ring counting to 100 %, a rising progress curve being drawn and four
/// checklist lines ticking off. Drawn with SwiftUI (no third-party animation asset, so no licence to track).
/// `isFinished` turns true when it is done (immediately with Reduce Motion).
private struct BuildingPlanView: View {
    @Binding var isFinished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    private static let duration = 3.6
    private static let steps: [LocalizedStringKey] = [
        "quiz.building.step.profile", "quiz.building.step.goals", "quiz.building.step.split", "quiz.building.step.progression",
    ]

    var body: some View {
        VStack(spacing: Spacing.lg) {
            MascotSpeech(
                image: "MascotExcited",
                message: isFinished ? "quiz.building.ready" : "quiz.building.title",
                mascotWidth: 140
            )
            ZStack {
                Ring(progress: progress)
                    .frame(width: 140, height: 140)
                VStack(spacing: 0) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(DSFont.numericLarge)
                        .foregroundStyle(DSColor.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            GrowthCurve()
                .trim(from: 0, to: progress)
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(height: 72)
                .padding(.horizontal, Spacing.md)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, key in
                    let done = progress >= Double(index + 1) / Double(Self.steps.count)
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? DSColor.accent : DSColor.textTertiary)
                        Text(key)
                            .font(DSFont.callout)
                            .foregroundStyle(done ? DSColor.textPrimary : DSColor.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-building")
        .task { await run() }
    }

    private func run() async {
        guard progress == 0 else { return }
        if reduceMotion {
            progress = 1
            isFinished = true
            return
        }
        let frames = 90
        for frame in 1...frames {
            try? await Task.sleep(for: .seconds(Self.duration / Double(frames)))
            // Ease out so the last percent points do not crawl.
            let t = Double(frame) / Double(frames)
            withAnimation(.linear(duration: Self.duration / Double(frames))) { progress = 1 - pow(1 - t, 1.6) }
        }
        progress = 1
        Haptics.play(.success)
        isFinished = true
    }
}

private struct Ring: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(DSColor.surfaceRaised, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DSColor.accentFill, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A curve that climbs with a few dips, like a strength progression chart.
private struct GrowthCurve: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGFloat] = [0.9, 0.78, 0.82, 0.6, 0.66, 0.42, 0.48, 0.25, 0.3, 0.08]
        var path = Path()
        for (index, value) in points.enumerated() {
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1),
                y: rect.minY + rect.height * value
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
