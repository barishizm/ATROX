import DataKit
import DesignSystem
import SwiftUI

// MARK: 1 · Name

struct NameStepView: View {
    @Bindable var model: OnboardingViewModel
    @FocusState private var focus: Field?
    private enum Field { case first, last }

    var body: some View {
        OnboardingPage(title: "onboarding.name.title", subtitle: "onboarding.name.subtitle") {
            VStack(spacing: Spacing.md) {
                field("onboarding.name.first", text: $model.firstName, field: .first, type: .givenName, id: "onboarding-first-name")
                    .submitLabel(.next)
                    .onSubmit { focus = .last }
                field("onboarding.name.last", text: $model.lastName, field: .last, type: .familyName, id: "onboarding-last-name")
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
            }
        }
        .task { focus = .first }
    }

    private func field(
        _ title: LocalizedStringKey, text: Binding<String>, field: Field, type: UITextContentType, id: String
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let isFocused = focus == field
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
            TextField("", text: text)
                .textContentType(type)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: HitTarget.button)
                .background(DSColor.surfaceRaised, in: shape)
                .overlay(shape.strokeBorder(isFocused ? DSColor.accent : DSColor.separator, lineWidth: isFocused ? 2 : 1))
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
    }
}

// MARK: 2 · Birth date

struct BirthDateStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.birth.title", subtitle: "onboarding.birth.subtitle") {
            DatePicker(
                "onboarding.birth.title",
                selection: Binding(get: { model.birthDateForDisplay }, set: { model.setBirthDate($0) }),
                in: model.birthDateRange,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboarding-birth-date")
        }
    }
}

/// Shown for under-16 users. Nothing has been saved.
struct UnderAgeView: View {
    let changeDate: @MainActor () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "heart.circle")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text("onboarding.blocked.title")
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("onboarding.blocked.message")
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            SecondaryButton("onboarding.blocked.change", action: changeDate)
                .accessibilityIdentifier("onboarding-blocked-change")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
        .accessibilityIdentifier("onboarding-blocked")
    }
}

// MARK: 3 · Sex

struct SexStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.sex.title") {
            VStack(spacing: Spacing.sm) {
                option(.male, "onboarding.sex.male")
                option(.female, "onboarding.sex.female")
                option(.unspecified, "onboarding.sex.unspecified")
            }
            Text("onboarding.sex.why")
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityIdentifier("onboarding-sex-why")
        }
    }

    private func option(_ value: Sex, _ title: LocalizedStringKey) -> some View {
        SelectableCard(title, isSelected: model.draft.sex == value) { model.setSex(value) }
            .accessibilityIdentifier("onboarding-sex-\(value.rawValue)")
    }
}

// MARK: 4 · Units

struct UnitsStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.units.title", subtitle: "onboarding.units.subtitle") {
            VStack(spacing: Spacing.sm) {
                SelectableCard("onboarding.units.metric", isSelected: model.draft.unitSystem == .metric) {
                    model.setUnitSystem(.metric)
                }
                .accessibilityIdentifier("onboarding-units-metric")
                SelectableCard("onboarding.units.imperial", isSelected: model.draft.unitSystem == .imperial) {
                    model.setUnitSystem(.imperial)
                }
                .accessibilityIdentifier("onboarding-units-imperial")
            }
        }
    }
}

// MARK: 5 · Height and weight

struct BodyStepView: View {
    @Bindable var model: OnboardingViewModel

    private var isMetric: Bool { model.draft.unitSystem == .metric }

    var body: some View {
        OnboardingPage(title: "onboarding.body.title") {
            HStack(alignment: .top, spacing: Spacing.md) {
                wheel("onboarding.body.height") { heightWheel }
                wheel("onboarding.body.weight") { weightWheel }
            }
            if model.isHealthAvailable { healthShortcut }
        }
        .alert(
            "onboarding.body.health.confirm.title",
            isPresented: Binding(
                get: { model.healthSuggestion != nil },
                set: { if !$0 { model.dismissHealthSuggestion() } }
            )
        ) {
            Button("onboarding.body.health.confirm.use") { model.applyHealthSuggestion() }
            Button("onboarding.body.health.confirm.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: healthSummary)
        }
    }

    /// Apple Health shortcut (P023): permission is asked only when this is pressed; the user confirms what is found.
    @ViewBuilder private var healthShortcut: some View {
        SecondaryButton("onboarding.body.health", systemImage: "heart.text.square") {
            Task { await model.requestHealthSuggestion() }
        }
        .disabled(model.isReadingHealth)
        .accessibilityIdentifier("onboarding-health")
        if model.healthFoundNothing {
            Text("onboarding.body.health.empty").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
                .accessibilityIdentifier("onboarding-health-empty")
        }
    }

    private var healthSummary: String {
        guard let found = model.healthSuggestion else { return "" }
        var lines: [String] = []
        if let height = found.heightCm {
            let unit: LengthUnit = isMetric ? .centimeters : .feetInches
            lines.append(String(localized: "onboarding.body.height") + ": "
                + LengthFormat.string(centimeters: height, unit: unit, locale: .current))
        }
        if let weight = found.weightKg {
            let unit: WeightUnit = isMetric ? .kilograms : .pounds
            lines.append(String(localized: "onboarding.body.weight") + ": "
                + WeightFormat.string(kilograms: weight, unit: unit, locale: .current))
        }
        if let birthDate = found.birthDate {
            lines.append(String(localized: "onboarding.body.health.birth") + ": "
                + birthDate.formatted(.dateTime.day().month().year()))
        }
        if let sex = found.sex {
            lines.append(String(localized: "onboarding.body.health.sex") + ": "
                + String(localized: sex == .male ? "onboarding.sex.male" : "onboarding.sex.female"))
        }
        return lines.joined(separator: "\n")
    }

    private func wheel<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            content().pickerStyle(.wheel).frame(height: 180).clipped()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var heightWheel: some View {
        if isMetric {
            Picker("onboarding.body.height", selection: Binding(
                get: { Int(model.draft.heightCm.rounded()).clamped(to: 100...250) },
                set: { model.setHeight(cm: Double($0)) }
            )) {
                ForEach(100...250, id: \.self) { Text("\($0) cm").tag($0) }
            }
            .accessibilityIdentifier("onboarding-height")
        } else {
            Picker("onboarding.body.height", selection: Binding(
                get: { Int(LengthFormat.inches(fromCentimeters: model.draft.heightCm).rounded()).clamped(to: 40...98) },
                set: { model.setHeight(cm: LengthFormat.centimeters(feet: $0 / 12, inches: $0 % 12)) }
            )) {
                ForEach(40...98, id: \.self) { Text("\($0 / 12)′ \($0 % 12)″").tag($0) }
            }
            .accessibilityIdentifier("onboarding-height")
        }
    }

    /// Metric: half-kilo steps (selection is the half-kilo count). Imperial: whole pounds.
    @ViewBuilder private var weightWheel: some View {
        if isMetric {
            Picker("onboarding.body.weight", selection: Binding(
                get: { Int((model.draft.weightKg * 2).rounded()).clamped(to: 60...600) },
                set: { model.setWeight(kg: Double($0) / 2) }
            )) {
                ForEach(60...600, id: \.self) { half in
                    Text(WeightFormat.string(kilograms: Double(half) / 2, unit: .kilograms, locale: .current)).tag(half)
                }
            }
            .accessibilityIdentifier("onboarding-weight")
        } else {
            Picker("onboarding.body.weight", selection: Binding(
                get: { Int(WeightUnit.pounds.value(fromKilograms: model.draft.weightKg).rounded()).clamped(to: 66...660) },
                set: { model.setWeight(kg: WeightUnit.pounds.kilograms(from: Double($0))) }
            )) {
                ForEach(66...660, id: \.self) { Text("\($0) lb").tag($0) }
            }
            .accessibilityIdentifier("onboarding-weight")
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

/// One selectable answer: the stored value plus its card texts.
private struct Option<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: String?
    var id: Value { value }

    /// `key` is the title's string key; the description lives under `<key>.detail`.
    init(_ value: Value, _ key: String, icon: String? = nil) {
        self.value = value
        self.title = LocalizedStringKey(key)
        self.detail = LocalizedStringKey(key + ".detail")
        self.icon = icon
    }
}

// MARK: 6 · Experience

struct ExperienceStepView: View {
    @Bindable var model: OnboardingViewModel

    private static let options: [Option<Experience>] = [
        Option(.noExperience, "onboarding.experience.none"),
        Option(.under6Months, "onboarding.experience.under6"),
        Option(.sixMonthsToTwoYears, "onboarding.experience.6to24"),
        Option(.twoToFiveYears, "onboarding.experience.2to5"),
        Option(.over5Years, "onboarding.experience.over5"),
    ]

    var body: some View {
        OnboardingPage(title: "onboarding.experience.title", subtitle: "onboarding.experience.subtitle") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.options) { option in
                    SelectableCard(option.title, subtitle: option.detail, isSelected: model.draft.experience == option.value) {
                        model.setExperience(option.value)
                    }
                    .accessibilityIdentifier("onboarding-experience-\(option.value.rawValue)")
                }
            }
        }
    }
}

// MARK: 7 · Goal

struct GoalStepView: View {
    @Bindable var model: OnboardingViewModel

    private static let options: [Option<Goal>] = [
        Option(.strength, "onboarding.goal.strength", icon: "bolt.fill"),
        Option(.muscleGain, "onboarding.goal.muscle", icon: "figure.strengthtraining.traditional"),
        Option(.fatLoss, "onboarding.goal.fat", icon: "flame.fill"),
        Option(.generalHealth, "onboarding.goal.health", icon: "heart.fill"),
    ]

    var body: some View {
        OnboardingPage(title: "onboarding.goal.title", subtitle: "onboarding.goal.subtitle") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.options) { option in
                    SelectableCard(
                        option.title, subtitle: option.detail, systemImage: option.icon,
                        isSelected: model.draft.goal == option.value
                    ) {
                        model.setGoal(option.value)
                    }
                    .accessibilityIdentifier("onboarding-goal-\(option.value.rawValue)")
                }
            }
        }
    }
}

// MARK: 8 · Weekly training days

struct FrequencyStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.frequency.title", subtitle: "onboarding.frequency.subtitle") {
            VStack(spacing: Spacing.lg) {
                Text("onboarding.frequency.days \(model.draft.weeklyFrequency)")
                    .font(DSFont.display)
                    .foregroundStyle(DSColor.accent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding-frequency-value")
                Stepper(
                    "onboarding.frequency.title",
                    value: Binding(get: { model.draft.weeklyFrequency }, set: { model.setWeeklyFrequency($0) }),
                    in: OnboardingRules.weeklyFrequencyRange
                )
                .labelsHidden()
                .accessibilityIdentifier("onboarding-frequency-stepper")
                HStack(spacing: Spacing.xs) {
                    ForEach(OnboardingRules.weeklyFrequencyRange, id: \.self) { day in
                        Button {
                            Haptics.play(.selection)
                            model.setWeeklyFrequency(day)
                        } label: {
                            Text("\(day)")
                                .font(DSFont.headline)
                                .foregroundStyle(model.draft.weeklyFrequency == day ? DSColor.onAccent : DSColor.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                                .background(
                                    model.draft.weeklyFrequency == day ? DSColor.accent : DSColor.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("onboarding.frequency.days \(day)")
                        .accessibilityAddTraits(model.draft.weeklyFrequency == day ? .isSelected : [])
                        .accessibilityIdentifier("onboarding-frequency-\(day)")
                    }
                }
            }
        }
    }
}

// MARK: 9 · Equipment

struct EquipmentStepView: View {
    @Bindable var model: OnboardingViewModel

    private static let options: [Option<EquipmentAccess>] = [
        Option(.fullGym, "onboarding.equipment.gym", icon: "building.2.fill"),
        Option(.homeBarbell, "onboarding.equipment.homeBarbell", icon: "house.fill"),
        Option(.homeDumbbell, "onboarding.equipment.homeDumbbell", icon: "dumbbell.fill"),
        Option(.bodyweightOnly, "onboarding.equipment.bodyweight", icon: "figure.core.training"),
    ]

    var body: some View {
        OnboardingPage(title: "onboarding.equipment.title", subtitle: "onboarding.equipment.subtitle") {
            VStack(spacing: Spacing.sm) {
                ForEach(Self.options) { option in
                    SelectableCard(
                        option.title, subtitle: option.detail, systemImage: option.icon,
                        isSelected: model.draft.equipment == option.value
                    ) {
                        model.setEquipment(option.value)
                    }
                    .accessibilityIdentifier("onboarding-equipment-\(option.value.rawValue)")
                }
            }
        }
    }
}

// MARK: 10 · Limitations

struct LimitationsStepView: View {
    @Bindable var model: OnboardingViewModel
    @FocusState private var noteFocused: Bool

    private static let titles: [BodyLimitation: LocalizedStringKey] = [
        .shoulder: "onboarding.limits.shoulder", .lowerBack: "onboarding.limits.lowerBack",
        .knee: "onboarding.limits.knee", .elbow: "onboarding.limits.elbow",
        .wrist: "onboarding.limits.wrist", .hip: "onboarding.limits.hip",
    ]

    var body: some View {
        OnboardingPage(title: "onboarding.limits.title", subtitle: "onboarding.limits.subtitle") {
            VStack(spacing: Spacing.sm) {
                ForEach(BodyLimitation.allCases, id: \.self) { area in
                    SelectableCard(
                        Self.titles[area] ?? "", isSelected: model.draft.limitations.contains(area), indicator: .checkbox
                    ) { model.toggleLimitation(area) }
                    .accessibilityIdentifier("onboarding-limits-\(area.rawValue)")
                }
                SelectableCard("onboarding.limits.none", isSelected: model.draft.noLimitations, indicator: .checkbox) {
                    noteFocused = false
                    model.toggleNoLimitations()
                }
                .accessibilityIdentifier("onboarding-limits-none")
                note
            }
        }
    }

    private var note: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("onboarding.limits.note").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            TextField("", text: $model.limitationNote, axis: .vertical)
                .lineLimit(2...4)
                .focused($noteFocused)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .padding(Spacing.md)
                .background(DSColor.surfaceRaised, in: shape)
                .overlay(shape.strokeBorder(noteFocused ? DSColor.accent : DSColor.separator, lineWidth: noteFocused ? 2 : 1))
                .accessibilityLabel("onboarding.limits.note")
                .accessibilityIdentifier("onboarding-limits-note")
        }
        .padding(.top, Spacing.sm)
    }
}
