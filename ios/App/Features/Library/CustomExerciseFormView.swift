import DataKit
import DesignSystem
import SwiftUI

/// Create / edit a custom exercise (P031): name, equipment, muscles, load rule and, optionally, a catalog exercise
/// it is "similar to" (its scoring settings are inherited).
struct CustomExerciseFormView: View {
    @Bindable var model: CustomExerciseFormModel
    var onSaved: (CustomExerciseSnapshot) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(AppContainer.self) private var container
    @State private var pickingSimilar = false

    var body: some View {
        NavigationStack {
            Form {
                Section("custom.form.name") {
                    TextField("custom.form.name.placeholder", text: $model.name)
                        .accessibilityIdentifier("custom-name")
                }
                Section {
                    Picker("custom.form.equipment", selection: $model.equipment) {
                        Text("library.equipment.none").tag(String?.none)
                        ForEach(ExerciseVocabulary.equipment, id: \.self) { raw in
                            Text(equipmentKey(raw)).tag(Optional(raw))
                        }
                    }
                    .accessibilityIdentifier("custom-equipment")
                }
                Section {
                    FlowChips(options: muscleOptions, selection: Binding(
                        get: { model.primaryMuscles }, set: { model.setPrimary($0) }
                    ))
                } header: {
                    Text("custom.form.muscles.primary")
                } footer: {
                    Text("custom.form.muscles.primary.footer")
                }
                Section("custom.form.muscles.secondary") {
                    FlowChips(options: muscleOptions, selection: Binding(
                        get: { model.secondaryMuscles }, set: { model.setSecondary($0) }
                    ))
                }
                Section {
                    Picker("custom.form.mechanic", selection: $model.mechanic) {
                        Text("custom.form.mechanic.none").tag(String?.none)
                        ForEach(ExerciseVocabulary.mechanics, id: \.self) { raw in
                            Text(LocalizedStringKey("exercise.mechanic.\(raw)")).tag(Optional(raw))
                        }
                    }
                    Picker("custom.form.level", selection: $model.level) {
                        ForEach(ExerciseVocabulary.levels, id: \.self) { raw in
                            Text(LocalizedStringKey("exercise.level.\(raw)")).tag(raw)
                        }
                    }
                    Toggle("custom.form.unilateral", isOn: $model.isUnilateral)
                }
                Section {
                    Picker("custom.form.load", selection: $model.loadConvention) {
                        ForEach(ExerciseVocabulary.loadConventions, id: \.self) { raw in
                            Text(LocalizedStringKey("exercise.load.\(raw)")).tag(raw)
                        }
                    }
                    .accessibilityIdentifier("custom-load")
                } footer: {
                    Text("custom.form.load.footer")
                }
                Section {
                    TextField("custom.form.steps.placeholder", text: $model.stepsText, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("custom.form.steps")
                } footer: {
                    Text("custom.form.steps.footer")
                }
                scoringSection
                if model.saveFailed {
                    Section { Text("custom.form.error.save").foregroundStyle(DSColor.error) }
                }
            }
            .navigationTitle(model.mode == .create ? "custom.form.title.new" : "custom.form.title.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("library.select.cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("custom.form.save") {
                        Task { if let saved = await model.save() { onSaved(saved) } }
                    }
                    .disabled(!model.isValid || model.isSaving)
                    .accessibilityIdentifier("custom-save")
                }
            }
            .sheet(isPresented: $pickingSimilar) {
                NavigationStack {
                    LibraryView(onAdd: { ids in pickSimilar(ids.first) }, singleSelection: true, catalogOnly: true)
                        .environment(container)
                }
            }
        }
        .interactiveDismissDisabled(model.isSaving)
        .accessibilityIdentifier("custom-form")
    }

    private var muscleOptions: [(id: String, label: Text)] {
        Muscle.allCases.map { ($0.rawValue, Text(verbatim: $0.localizedName(locale: locale))) }
    }

    private var scoringSection: some View {
        Section {
            if let similar = model.similar {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("custom.form.similar.current").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        Text(verbatim: similar.name(languageCode: locale.language.languageCode?.identifier == "tr" ? "tr" : "en"))
                    }
                    Spacer()
                    Button("custom.form.similar.clear", role: .destructive) { model.setSimilar(nil) }
                        .buttonStyle(.borderless)
                }
            } else {
                Text("custom.form.similar.none").foregroundStyle(DSColor.textSecondary)
            }
            Button("custom.form.similar.choose") { pickingSimilar = true }
                .accessibilityIdentifier("custom-similar")
        } header: {
            Text("custom.form.scoring")
        } footer: {
            Text("custom.form.scoring.footer")
        }
    }

    private func pickSimilar(_ id: String?) {
        guard let id, let store = container.modelContainer else { return }
        Task {
            let detail = try? await Task.detached { try ExerciseDetail.load(id: id, in: store) }.value
            if let detail { model.setSimilar(detail) }
        }
    }
}
