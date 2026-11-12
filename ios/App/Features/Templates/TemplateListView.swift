import DataKit
import DesignSystem
import SwiftUI

/// Ready-made programs (P034): the two that fit the user's profile first, then all of them.
struct TemplateListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: TemplateListModel?
    @State private var failed = false
    @State private var opened: String?

    var body: some View {
        Group {
            if let model {
                list(model)
            } else if failed {
                ErrorState(message: "template.error.load") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("template.list.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("template-list-root")
    }

    private var languageCode: String { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }

    private func prepare() async {
        failed = false
        if let made = await container.makeTemplateListModel() { model = made } else { failed = true }
    }

    private func list(_ model: TemplateListModel) -> some View {
        List {
            if !model.recommended.isEmpty {
                Section("template.list.recommended") {
                    ForEach(model.recommended, id: \.id) { row($0, model: model, highlighted: true) }
                }
            }
            Section(model.recommended.isEmpty ? "template.list.all" : "template.list.others") {
                ForEach(model.others, id: \.id) { row($0, model: model, highlighted: false) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationDestination(item: $opened) { id in
            if let template = model.template(id: id) { TemplateDetailView(model: model, template: template) }
        }
    }

    private func row(_ template: ProgramTemplate, model: TemplateListModel, highlighted: Bool) -> some View {
        Button { opened = template.id } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(verbatim: template.name.resolve(languageCode: languageCode))
                        .font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    if highlighted { TagChip("template.badge.fit", style: .accent) }
                }
                Text(verbatim: template.audience.resolve(languageCode: languageCode))
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                Text("template.summary \(template.daysPerWeek) \(template.estimatedMinutes)")
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            .padding(.vertical, Spacing.xs)
        }
        .accessibilityIdentifier("template-row-\(template.id)")
    }
}

/// One template: who it is for, the days with their exercises (as personalized for the user) and "use this".
struct TemplateDetailView: View {
    let model: TemplateListModel
    let template: ProgramTemplate
    @Environment(\.locale) private var locale
    @State private var useAlternatives = false
    @State private var openedRoutine: UUID?

    private var languageCode: String { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }

    var body: some View {
        let personalized = model.personalized(template)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                notes(personalized)
                ForEach(Array(personalized.days.enumerated()), id: \.offset) { _, day in dayCard(day) }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(DSColor.background)
        .navigationTitle(template.name.resolve(languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { footer }
        .alert("template.error.use", isPresented: Bindable(model).errorOccurred) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .navigationDestination(item: $openedRoutine) { RoutineEditorView(routineId: $0) }
        .accessibilityIdentifier("template-detail-root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: template.summary.resolve(languageCode: languageCode))
                .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
            Text(verbatim: template.audience.resolve(languageCode: languageCode))
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            HStack(spacing: Spacing.sm) {
                TagChip("template.chip.days \(template.daysPerWeek)", systemImage: "calendar")
                TagChip("template.chip.minutes \(template.estimatedMinutes)", systemImage: "clock")
                TagChip(template.level == .beginner ? "template.level.beginner" : "template.level.intermediate")
            }
        }
    }

    @ViewBuilder
    private func notes(_ personalized: PersonalizedTemplate) -> some View {
        if personalized.replacedCount > 0 || personalized.flaggedCount > 0 || personalized.unavailableCount > 0 {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if personalized.replacedCount > 0 {
                        Label("template.note.replaced \(personalized.replacedCount)", systemImage: "arrow.triangle.swap")
                    }
                    if personalized.unavailableCount > 0 {
                        Label("template.note.unavailable \(personalized.unavailableCount)", systemImage: "exclamationmark.circle")
                    }
                    if personalized.flaggedCount > 0 {
                        Label("template.note.flagged \(personalized.flaggedCount)", systemImage: "exclamationmark.triangle")
                        Toggle("template.note.useAlternatives", isOn: $useAlternatives)
                            .accessibilityIdentifier("template-use-alternatives")
                    }
                }
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textPrimary)
            }
        }
    }

    private func dayCard(_ day: PersonalizedDay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: day.name.resolve(languageCode: languageCode))
                .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, exercise in exerciseRow(exercise) }
                }
            }
        }
    }

    private func exerciseRow(_ exercise: PersonalizedExercise) -> some View {
        let shownId = useAlternatives ? (exercise.alternativeId ?? exercise.exerciseId) : exercise.exerciseId
        let target = exercise.target
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: model.exerciseName(shownId, languageCode: languageCode))
                    .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                Text("template.exercise.target \(target.sets) \(target.repsMin) \(target.repsMax)")
                    .font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
            }
            if exercise.isFlagged, !useAlternatives {
                if let alternative = exercise.alternativeId {
                    Label {
                        Text("template.exercise.alternative \(model.exerciseName(alternative, languageCode: languageCode))")
                    } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(DSFont.caption).foregroundStyle(DSColor.warning)
                } else {
                    Label("template.exercise.flagged", systemImage: "exclamationmark.triangle")
                        .font(DSFont.caption).foregroundStyle(DSColor.warning)
                }
            } else if exercise.replacedId != nil {
                Label("template.exercise.replaced", systemImage: "arrow.triangle.swap")
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        PrimaryButton("template.action.use", isLoading: model.isInstalling) {
            Task {
                openedRoutine = await model.use(template, languageCode: languageCode, useAlternatives: useAlternatives)
            }
        }
        .accessibilityIdentifier("template-use")
        .padding(Spacing.lg)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(DSColor.background)
    }
}
