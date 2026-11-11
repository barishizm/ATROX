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
        ChoiceRow(title: title, isSelected: model.draft.sex == value) { model.setSex(value) }
            .accessibilityIdentifier("onboarding-sex-\(value.rawValue)")
    }
}

/// Full-width single-choice row.
struct ChoiceRow: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        Button(action: action) {
            HStack {
                Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: HitTarget.button)
            .background(DSColor.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: 4 · Units

struct UnitsStepView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "onboarding.units.title", subtitle: "onboarding.units.subtitle") {
            VStack(spacing: Spacing.sm) {
                ChoiceRow(title: "onboarding.units.metric", isSelected: model.draft.unitSystem == .metric) {
                    model.setUnitSystem(.metric)
                }
                .accessibilityIdentifier("onboarding-units-metric")
                ChoiceRow(title: "onboarding.units.imperial", isSelected: model.draft.unitSystem == .imperial) {
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
            // Room for the Apple Health shortcut; wired up in P023.
            SecondaryButton("onboarding.body.health", systemImage: "heart.text.square") {}
                .disabled(true)
                .accessibilityIdentifier("onboarding-health")
            Text("onboarding.body.health.soon").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
        }
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
