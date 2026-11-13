import DataKit
import DesignSystem
import SwiftUI

/// Exercise detail (P031): start/end image loop, muscle map, tags, steps, the user's own data (empty until phase 6)
/// and a note on how the exercise is scored.
struct ExerciseDetailView: View {
    let exerciseID: String
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExerciseDetailModel?
    @State private var editing: CustomExerciseFormModel?
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var unavailable = false
    @State private var history: ExerciseHistoryModel?
    @State private var scoreText: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if unavailable {
                ErrorState(message: "exercise.detail.error.load") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("exercise.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("exercise-detail-root")
    }

    @ViewBuilder
    private func content(_ model: ExerciseDetailModel) -> some View {
        switch model.state {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "exercise.detail.error.load") { Task { await model.load() } }
        case .missing:
            EmptyState(systemImage: "questionmark.circle", title: "exercise.detail.missing.title",
                       message: "exercise.detail.missing.message")
        case .loaded(let detail): loaded(detail, model: model)
        }
    }

    private func loaded(_ detail: ExerciseDetail, model: ExerciseDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if detail.frames.isEmpty {
                    EmptyView()
                } else {
                    ExerciseImageCarousel(frames: detail.frames)
                }
                header(detail, model: model)
                musclesSection(detail)
                instructionsSection(detail, model: model)
                yourDataSection
                if let note = detail.scoreNote { scoreNote(note) }
            }
            .padding(Spacing.md)
        }
        .toolbar {
            if model.canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("exercise.detail.edit", systemImage: "pencil") { Task { await startEditing(model) } }
                        Button("exercise.detail.delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("exercise.detail.menu")
                    .accessibilityIdentifier("exercise-detail-menu")
                }
            }
        }
        .confirmationDialog("exercise.detail.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("exercise.detail.delete", role: .destructive) {
                Task {
                    if await model.delete() { dismiss() } else { deleteFailed = true }
                }
            }
        } message: {
            Text("exercise.detail.delete.message")
        }
        .alert("exercise.detail.delete.failed", isPresented: $deleteFailed) {
            Button("library.filter.done", role: .cancel) {}
        }
        .sheet(item: $editing) { form in
            CustomExerciseFormView(model: form) { _ in
                editing = nil
                Task { await model.load() }
            }
        }
    }

    private func header(_ detail: ExerciseDetail, model: ExerciseDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: detail.name(languageCode: model.languageCode))
                .font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            FlowTags {
                if detail.isCustom { TagChip("exercise.detail.custom", systemImage: "person.fill", style: .accent) }
                TagChip(equipmentKey(detail.equipment), systemImage: "dumbbell")
                if let mechanic = detail.mechanic { TagChip(LocalizedStringKey("exercise.mechanic.\(mechanic)")) }
                TagChip(LocalizedStringKey("exercise.level.\(detail.level)"), systemImage: "chart.bar")
                if detail.isUnilateral { TagChip("exercise.detail.unilateral") }
                if let load = detail.scoring.loadConvention {
                    TagChip(LocalizedStringKey("exercise.load.\(load)"), systemImage: "scalemass")
                }
            }
        }
    }

    private func musclesSection(_ detail: ExerciseDetail) -> some View {
        let primary = detail.primaryMuscles.compactMap(Muscle.init(rawValue:))
        let secondary = detail.secondaryMuscles.compactMap(Muscle.init(rawValue:))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise.detail.muscles").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    MuscleMapView(primary: primary, secondary: secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                    legend("exercise.detail.muscles.primary", muscles: primary, tint: DSColor.accent)
                    if !secondary.isEmpty {
                        legend("exercise.detail.muscles.secondary", muscles: secondary, tint: DSColor.accent.opacity(0.45))
                    }
                }
            }
        }
    }

    private func legend(_ title: LocalizedStringKey, muscles: [Muscle], tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle().fill(tint).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                Text(verbatim: muscles.map { $0.localizedName(locale: locale) }.joined(separator: ", "))
                    .font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func instructionsSection(_ detail: ExerciseDetail, model: ExerciseDetailModel) -> some View {
        let steps = detail.instructions(languageCode: model.languageCode)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise.detail.instructions").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if steps.isEmpty {
                Text("exercise.detail.instructions.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        Text(verbatim: "\(offset + 1)")
                            .font(DSFont.numericSmall).foregroundStyle(DSColor.onAccent)
                            .frame(width: 26, height: 26).background(DSColor.accent, in: Circle())
                            .accessibilityHidden(true)
                        Text(verbatim: step).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The user's own numbers for this exercise from the workout history (P042); the score arrives with phase 6.
    private var yourDataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise.detail.yourData").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Spacing.md) {
                        stat("exercise.detail.bestSet", history?.heaviestText)
                        stat("exercise.detail.e1rm", history?.bestE1rmText)
                        stat(
                            "exercise.detail.lastPerformed",
                            history?.progress.lastDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) }
                        )
                        stat("exercise.detail.score", scoreText)
                    }
                    NavigationLink {
                        ExerciseScoreView(exerciseID: exerciseID)
                    } label: {
                        Label("scorescreen.open", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .accessibilityIdentifier("open-exercise-score")
                    if history?.isEmpty == false {
                        NavigationLink(value: WorkoutRoute.exerciseHistory(id: exerciseID)) {
                            Label("exercisehistory.open", systemImage: "chart.xyaxis.line")
                        }
                        .accessibilityIdentifier("open-exercise-history")
                    } else {
                        Text("exercise.detail.yourData.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier("exercise-your-data")
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).dsOverline()
            Text(verbatim: value ?? "—").font(DSFont.numericMedium)
                .foregroundStyle(value == nil ? DSColor.textTertiary : DSColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func scoreNote(_ note: ScoreNote) -> some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: note == .notScored ? "minus.circle" : "info.circle")
                    .foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("exercise.scorenote.title").font(DSFont.callout.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(LocalizedStringKey("exercise.scorenote.\(note.rawValue)"))
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exercise-score-note")
    }

    private func startEditing(_ model: ExerciseDetailModel) async {
        guard let userId = model.userId, let snapshot = await model.customSnapshot() else { return }
        editing = CustomExerciseFormModel(userId: userId, repository: model.customRepository, editing: snapshot)
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeExerciseDetailModel(id: exerciseID) else {
            unavailable = true
            return
        }
        unavailable = false
        created.languageCode = locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
        model = created
        await created.load()
        if let context = await container.makeHistoryContext() {
            let data = ExerciseHistoryModel(ref: ActiveWorkoutView.ref(exerciseID), context: context)
            await data.load()
            history = data
        }
        await loadScore()
    }

    /// The score shown in "Your data": the preferred reference group's, straight from the history.
    private func loadScore() async {
        guard let service = container.scoreService, let user = await container.currentUser() else { return }
        let group = await service.preferredPopulation(userId: user.id)
        let evaluation = await service.evaluation(userId: user.id, exerciseId: exerciseID, population: group)
        scoreText = evaluation.map { Int($0.score.score.rounded()).formatted() }
    }
}

extension CustomExerciseFormModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Wrapping row of tags.
private struct FlowTags<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: Spacing.sm) { content }
    }
}
