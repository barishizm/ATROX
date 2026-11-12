import DataKit
import DesignSystem
import SwiftUI

/// The exercises of one routine day (P033): add from the library, drag to reorder, swipe to delete or duplicate,
/// group into supersets, tap to edit the targets. Every change is saved at once; the toolbar undoes the last ones.
struct RoutineDayView: View {
    let routineId: UUID
    let dayId: UUID
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @Environment(\.locale) private var locale
    @State private var model: RoutineEditorModel?
    @State private var failed = false
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<UUID> = []
    @State private var editing: RoutineExerciseSnapshot?
    @State private var picking = false
    @State private var dayName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if failed {
                ErrorState(message: "routine.error.load") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("routine.day.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("routine-day-root")
    }

    private var languageCode: String { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }

    private func prepare() async {
        failed = false
        guard let made = await container.makeRoutineEditorModel(routineId: routineId) else {
            failed = true
            return
        }
        made.languageCode = languageCode
        model = made
        await made.load()
        dayName = made.day(dayId)?.name ?? ""
    }

    @ViewBuilder
    private func content(_ model: RoutineEditorModel) -> some View {
        switch model.loadState {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "routine.error.load") { Task { await model.load() } }
        case .missing:
            EmptyState(systemImage: "questionmark.circle", title: "routine.missing.title", message: "routine.missing.message")
        case .loaded:
            if let day = model.day(dayId) {
                list(day, model: model)
            } else {
                EmptyState(systemImage: "questionmark.circle", title: "routine.missing.title", message: "routine.missing.message")
            }
        }
    }

    private func list(_ day: RoutineDaySnapshot, model: RoutineEditorModel) -> some View {
        List(selection: $selection) {
            Section {
                TextField("routine.day.namePrompt", text: $dayName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitName(model) }
                    .accessibilityIdentifier("routine-day-name-field")
            }
            .selectionDisabled()
            Section {
                if day.exercises.isEmpty {
                    EmptyState(
                        systemImage: "dumbbell", title: "routine.day.empty.title", message: "routine.day.empty.message"
                    )
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
                }
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                    row(exercise, index: index, day: day, model: model)
                }
                .onMove { source, destination in
                    Task { await model.moveExercises(dayId: dayId, from: source, to: destination) }
                }
            }
            Section {
                Button { picking = true } label: { Label("routine.day.addExercise", systemImage: "plus") }
                    .accessibilityIdentifier("routine-add-exercise")
            }
            .selectionDisabled()
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { toolbar(model) }
        .sheet(isPresented: $picking) {
            NavigationStack {
                LibraryView(onAdd: { ids in
                    picking = false
                    Task { await model.addExercises(dayId: dayId, itemIDs: ids) }
                })
            }
        }
        .sheet(item: $editing) { exercise in
            RoutineExerciseSheet(
                name: model.name(of: exercise.ref), input: exercise.input
            ) { input in
                Task { await model.update(exercise, with: input) }
            }
        }
        .alert("routine.error.save", isPresented: Bindable(model).errorOccurred) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName(model) } }
        .onChange(of: editMode) { _, mode in if !mode.isEditing { selection = [] } }
        .onDisappear { commitName(model) }
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: RoutineEditorModel) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await presenter.start(routineId: routineId, dayId: dayId, container: container) }
            } label: { Image(systemName: "play.fill") }
                .accessibilityLabel("workout.start.day")
                .accessibilityIdentifier("routine-day-start")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await model.undo() } } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityLabel("routine.action.undo")
                .accessibilityIdentifier("routine-undo")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(editMode.isEditing ? "routine.action.finishEdit" : "routine.action.reorder") {
                editMode = editMode.isEditing ? .inactive : .active
            }
            .accessibilityIdentifier("routine-reorder")
        }
        if editMode.isEditing {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let ids = Array(selection)
                    selection = []
                    editMode = .inactive
                    Task { await model.makeSuperset(ids) }
                } label: {
                    Text("routine.superset.group \(selection.count)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.count < 2)
                .accessibilityIdentifier("routine-make-superset")
            }
        }
    }

    // MARK: Rows

    private func row(
        _ exercise: RoutineExerciseSnapshot, index: Int, day: RoutineDaySnapshot, model: RoutineEditorModel
    ) -> some View {
        let group = exercise.input.supersetGroup
        let previous = index > 0 ? day.exercises[index - 1].input.supersetGroup : nil
        let next = index + 1 < day.exercises.count ? day.exercises[index + 1].input.supersetGroup : nil
        let joinsPrevious = group != nil && group == previous
        let joinsNext = group != nil && group == next
        return HStack(spacing: Spacing.md) {
            ExerciseThumbnail(fileName: model.item(for: exercise.ref)?.thumbnailName)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: model.name(of: exercise.ref))
                    .font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                targetSummary(exercise.input)
                if let letter = model.supersetLetter(of: exercise, in: day), !joinsPrevious {
                    TagChip("routine.superset.badge \(letter)", style: .accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.leading, group == nil ? 0 : Spacing.sm)
        .overlay(alignment: .leading) {
            if group != nil {
                Rectangle().fill(DSColor.accent).frame(width: 3)
                    .padding(.top, joinsPrevious ? 0 : Spacing.sm)
                    .padding(.bottom, joinsNext ? 0 : Spacing.sm)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if !editMode.isEditing { editing = exercise } })
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.md, bottom: 0, trailing: Spacing.md))
        .listRowSeparator(joinsNext ? .hidden : .visible)
        .tag(exercise.id)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { await model.deleteExercise(exercise.id) } } label: {
                Label("routine.action.delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { Task { await model.duplicateExercise(exercise.id) } } label: {
                Label("routine.action.duplicate", systemImage: "plus.square.on.square")
            }
            .tint(DSColor.accent)
        }
        .contextMenu {
            Button { editing = exercise } label: { Label("routine.action.edit", systemImage: "slider.horizontal.3") }
            if group != nil {
                Button { Task { await model.leaveSuperset(exercise.id) } } label: {
                    Label("routine.superset.leave", systemImage: "link.badge.plus")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routine-exercise-\(index)")
    }

    /// "3 × 8–12 · RIR 2 · 1:30"
    private func targetSummary(_ input: RoutineExerciseInput) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(verbatim: Self.setsAndReps(input))
            if let rir = input.targetRir { Text(verbatim: "·"); Text("routine.summary.rir \(rir)") }
            if let rest = input.restSeconds { Text(verbatim: "·"); Text(verbatim: Self.clock(rest)) }
        }
        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
    }

    static func setsAndReps(_ input: RoutineExerciseInput) -> String {
        switch (input.targetRepsMin, input.targetRepsMax) {
        case let (low?, high?): low == high ? "\(input.targetSets) × \(low)" : "\(input.targetSets) × \(low)–\(high)"
        case let (low?, nil): "\(input.targetSets) × \(low)+"
        case let (nil, high?): "\(input.targetSets) × ≤\(high)"
        case (nil, nil): "\(input.targetSets) ×"
        }
    }

    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private func commitName(_ model: RoutineEditorModel) {
        let trimmed = dayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dayName = model.day(dayId)?.name ?? ""
            return
        }
        Task { await model.renameDay(dayId, to: trimmed) }
    }
}
