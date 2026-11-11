import DataKit
import DesignSystem
import SwiftUI

/// Edits every onboarding answer. The unit system is changed in Settings.
struct ProfileEditView: View {
    let model: ProfileModel
    @State private var edit: ProfileEditModel?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let edit {
                form(edit)
            } else if model.profile == nil {
                EmptyState(systemImage: "person.crop.circle.badge.questionmark", title: "profile.edit.missing")
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("profile.edit.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if edit == nil, let input = model.profile?.input { edit = ProfileEditModel(profile: input) }
        }
    }

    private func form(_ edit: ProfileEditModel) -> some View {
        @Bindable var edit = edit
        return Form {
            Section("profile.edit.section.identity") {
                TextField("onboarding.name.first", text: $edit.firstName)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("profile-edit-first-name")
                TextField("onboarding.name.last", text: $edit.lastName)
                    .textContentType(.familyName)
                DatePicker("profile.edit.birthDate", selection: $edit.birthDate, in: edit.birthDateRange, displayedComponents: .date)
                if edit.birthDateCheck == .tooYoung {
                    Text("profile.edit.ageError").font(DSFont.footnote).foregroundStyle(DSColor.error)
                }
                Picker("profile.edit.sex", selection: $edit.sex) {
                    Text("onboarding.sex.male").tag(Sex.male)
                    Text("onboarding.sex.female").tag(Sex.female)
                    Text("onboarding.sex.unspecified").tag(Sex.unspecified)
                }
                HeightPicker(heightCm: $edit.heightCm, unitSystem: edit.unitSystem)
            }
            Section("profile.edit.section.training") {
                Picker("profile.edit.experience", selection: $edit.experience) {
                    Text("onboarding.experience.none").tag(Experience.noExperience)
                    Text("onboarding.experience.under6").tag(Experience.under6Months)
                    Text("onboarding.experience.6to24").tag(Experience.sixMonthsToTwoYears)
                    Text("onboarding.experience.2to5").tag(Experience.twoToFiveYears)
                    Text("onboarding.experience.over5").tag(Experience.over5Years)
                }
                Picker("profile.edit.goal", selection: $edit.goal) {
                    Text("onboarding.goal.strength").tag(Goal.strength)
                    Text("onboarding.goal.muscle").tag(Goal.muscleGain)
                    Text("onboarding.goal.fat").tag(Goal.fatLoss)
                    Text("onboarding.goal.health").tag(Goal.generalHealth)
                }
                Stepper(value: $edit.weeklyFrequency, in: OnboardingRules.weeklyFrequencyRange) {
                    Text("onboarding.frequency.days \(edit.weeklyFrequency)")
                }
                Picker("profile.edit.equipment", selection: $edit.equipment) {
                    Text("onboarding.equipment.gym").tag(EquipmentAccess.fullGym)
                    Text("onboarding.equipment.homeBarbell").tag(EquipmentAccess.homeBarbell)
                    Text("onboarding.equipment.homeDumbbell").tag(EquipmentAccess.homeDumbbell)
                    Text("onboarding.equipment.bodyweight").tag(EquipmentAccess.bodyweightOnly)
                }
            }
            Section("profile.edit.section.limitations") {
                ForEach(BodyLimitation.allCases, id: \.self) { area in
                    Toggle(Self.title(for: area), isOn: Binding(
                        get: { edit.limitations.contains(area) },
                        set: { _ in edit.toggle(area) }
                    ))
                }
                TextField("onboarding.limits.note", text: Binding(get: { edit.limitationNote }, set: { edit.setNote($0) }), axis: .vertical)
            }
            if model.actionFailed {
                Text("profile.edit.error").font(DSFont.footnote).foregroundStyle(DSColor.error)
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.edit.save") {
                    isSaving = true
                    Task {
                        if await model.saveProfile(edit.input()) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(!edit.canSave || !edit.hasChanges || isSaving)
                .accessibilityIdentifier("profile-edit-save")
            }
        }
    }

    private static func title(for area: BodyLimitation) -> LocalizedStringKey {
        switch area {
        case .shoulder: "onboarding.limits.shoulder"
        case .lowerBack: "onboarding.limits.lowerBack"
        case .knee: "onboarding.limits.knee"
        case .elbow: "onboarding.limits.elbow"
        case .wrist: "onboarding.limits.wrist"
        case .hip: "onboarding.limits.hip"
        }
    }
}

/// Height in centimeters (metric) or whole inches shown as feet and inches (imperial). Stored value is cm.
private struct HeightPicker: View {
    @Binding var heightCm: Double
    let unitSystem: UnitSystem

    var body: some View {
        if unitSystem == .metric {
            Picker("onboarding.body.height", selection: Binding(
                get: { min(max(Int(heightCm.rounded()), 100), 250) },
                set: { heightCm = Double($0) }
            )) {
                ForEach(100...250, id: \.self) { Text(verbatim: "\($0) cm").tag($0) }
            }
        } else {
            Picker("onboarding.body.height", selection: Binding(
                get: { min(max(Int(LengthFormat.inches(fromCentimeters: heightCm).rounded()), 40), 98) },
                set: { heightCm = LengthFormat.centimeters(feet: $0 / 12, inches: $0 % 12) }
            )) {
                ForEach(40...98, id: \.self) { Text(verbatim: "\($0 / 12)′ \($0 % 12)″").tag($0) }
            }
        }
    }
}
