import DataKit
import DesignSystem
import SwiftUI

/// A finished workout (P042): exercises, sets, records, notes; edit mode for set values, adding and removing; delete
/// (with undo in the list), repeat and convert to a program.
struct WorkoutDetailView: View {
    let workoutId: UUID
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @Environment(\.dismiss) private var dismiss
    @State private var model: WorkoutDetailModel?
    @State private var unavailable = false
    @State private var editingSet: SetEdit?
    @State private var nameText = ""
    @State private var notesText = ""
    @State private var confirmsDelete = false
    @State private var naming = false
    @State private var programName = ""
    @State private var adding = false
    @State private var notice: LocalizedStringKey?
    @State private var repeatBlocked = false

    struct SetEdit: Identifiable {
        let setId: UUID
        let weightText: String
        let repsText: String
        let type: SetType
        var id: UUID { setId }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if unavailable {
                ErrorState(message: "history.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("history.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("workout-detail-root")
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let context = await container.makeHistoryContext() else {
            unavailable = true
            return
        }
        unavailable = false
        let created = WorkoutDetailModel(id: workoutId, context: context, events: container.historyEvents)
        model = created
        await created.load()
        nameText = created.workout?.name ?? ""
        notesText = created.workout?.notes ?? ""
    }

    @ViewBuilder
    private func content(_ model: WorkoutDetailModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else if let workout = model.workout {
            loaded(workout, model: model)
        } else {
            EmptyState(systemImage: "questionmark.circle", title: "history.detail.missing.title", message: "history.detail.missing.message")
        }
    }

    private func loaded(_ workout: WorkoutSnapshot, model: WorkoutDetailModel) -> some View {
        List {
            headerSection(workout, model: model)
            ForEach(workout.exercises) { exercise in exerciseSection(exercise, model: model) }
            if model.isEditing {
                Section { Button("history.addExercise", systemImage: "plus") { adding = true }.accessibilityIdentifier("history-add-exercise") }
            }
            actionsSection(workout, model: model)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isEditing ? "history.done" : "history.edit") {
                    if model.isEditing { Task { await model.saveDetails(name: nameText, notes: notesText) } }
                    model.isEditing.toggle()
                }
                .accessibilityIdentifier("history-edit-toggle")
            }
        }
        .onChange(of: model.wasDeleted) { if model.wasDeleted { dismiss() } }
        .sheet(item: $editingSet) { edit in
            SetEditSheet(edit: edit, unitSymbol: model.context.unit.symbol) { weight, reps, type in
                let saved = await model.saveSet(edit.setId, weightText: weight, repsText: reps, type: type)
                if saved { editingSet = nil }
            } delete: {
                await model.removeSet(edit.setId)
                editingSet = nil
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                LibraryView(onAdd: { ids in
                    adding = false
                    Task { for id in ids { await model.addExercise(ActiveWorkoutView.ref(id)) } }
                })
            }
        }
        .confirmationDialog("history.delete.confirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("history.delete", role: .destructive) {
                Task { await model.delete(title: workout.name ?? String(localized: "workout.title.default")) }
            }
        } message: {
            Text("history.delete.message")
        }
        .alert("history.convert.title", isPresented: $naming) {
            TextField("history.convert.placeholder", text: $programName)
            Button("history.convert.create") {
                Task {
                    let name = programName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    if await model.convertToRoutine(name: name, dayName: String(localized: "history.convert.day")) {
                        notice = "history.convert.done"
                    }
                }
            }
            Button("workout.cancel.keep", role: .cancel) {}
        }
        .alert("history.repeat.blocked", isPresented: $repeatBlocked) { Button("workout.ok", role: .cancel) {} }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("workout.ok", role: .cancel) {}
        }
        .alert("workout.error.title", isPresented: Binding(get: { model.errorKey != nil }, set: { if !$0 { model.errorKey = nil } })) {
            Button("workout.ok", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(model.errorKey ?? "history.error"))
        }
    }

    // MARK: Sections

    private func headerSection(_ workout: WorkoutSnapshot, model: WorkoutDetailModel) -> some View {
        Section {
            if model.isEditing {
                TextField("summary.name.placeholder", text: $nameText).accessibilityIdentifier("history-name")
                TextField("summary.notes.placeholder", text: $notesText, axis: .vertical).lineLimit(2...6)
                    .accessibilityIdentifier("history-notes")
            } else {
                Text(verbatim: workout.name ?? String(localized: "workout.title.default")).font(DSFont.title)
                if let notes = workout.notes { Text(verbatim: notes).font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
            }
            LabeledContent("history.detail.date") {
                Text(workout.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
            }
            LabeledContent("summary.duration") { Text(verbatim: model.durationText) }
            LabeledContent("summary.volume") { Text(verbatim: model.volumeText).monospacedDigit() }
            HStack(spacing: Spacing.xs) {
                Text("summary.feeling")
                Spacer()
                ForEach(1...5, id: \.self) { value in
                    Button {
                        Task { await model.setRating(workout.rating == value ? nil : value) }
                    } label: {
                        Image(systemName: (workout.rating ?? 0) >= value ? "star.fill" : "star")
                            .foregroundStyle((workout.rating ?? 0) >= value ? DSColor.accent : DSColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isEditing)
                    .accessibilityLabel("summary.feeling.value \(value)")
                }
            }
        }
    }

    private func exerciseSection(_ exercise: WorkoutExerciseSnapshot, model: WorkoutDetailModel) -> some View {
        Section {
            ForEach(exercise.sets) { set in setRow(set, model: model) }
            if model.isEditing {
                Button("history.addSet", systemImage: "plus.circle") { Task { await model.addSet(to: exercise.id) } }
                    .accessibilityIdentifier("history-add-set")
            }
        } header: {
            HStack {
                NavigationLink(value: WorkoutRoute.exerciseHistory(id: HistoryContext.id(of: exercise.ref))) {
                    Text(verbatim: model.name(of: exercise.ref)).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                }
                Spacer()
                if model.isEditing {
                    Button(role: .destructive) { Task { await model.removeExercise(exercise.id) } } label: { Image(systemName: "trash") }
                        .accessibilityLabel("history.removeExercise")
                }
            }
            .textCase(nil)
        }
    }

    private func setRow(_ set: SetSnapshot, model: WorkoutDetailModel) -> some View {
        let working = set.input.setType == .working
        return Button {
            guard model.isEditing else { return }
            editingSet = SetEdit(
                setId: set.id, weightText: model.editableWeight(set.input.weightKg), repsText: "\(set.input.reps)", type: set.input.setType
            )
        } label: {
            HStack {
                Text(verbatim: working ? "" : Self.badge(set.input.setType)).font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary).frame(width: 20)
                Text(verbatim: model.context.setText(set.input)).font(DSFont.numericSmall)
                    .foregroundStyle(set.input.isCompleted ? DSColor.textPrimary : DSColor.textTertiary)
                if let rir = set.input.rir {
                    Text("history.rir \(rir)").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                if let kind = model.recordKinds[set.id]?.first {
                    Label(ActiveWorkoutView.recordName(kind), systemImage: "trophy.fill")
                        .font(DSFont.caption.weight(.semibold)).foregroundStyle(DSColor.accent)
                        .accessibilityIdentifier("history-set-record")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            if model.isEditing {
                Button("history.delete", role: .destructive) { Task { await model.removeSet(set.id) } }
            }
        }
        .accessibilityIdentifier("history-set-row")
    }

    private static func badge(_ type: SetType) -> String {
        switch type {
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        case .working: ""
        }
    }

    private func actionsSection(_ workout: WorkoutSnapshot, model: WorkoutDetailModel) -> some View {
        Section {
            Button("history.repeat", systemImage: "arrow.counterclockwise") {
                Task {
                    if await presenter.startRepeating(workout, container: container) == false { repeatBlocked = true }
                }
            }
            .accessibilityIdentifier("history-repeat")
            Button("history.convert", systemImage: "list.bullet.rectangle") {
                programName = workout.name ?? ""
                naming = true
            }
            .accessibilityIdentifier("history-convert")
            Button("history.delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                .accessibilityIdentifier("history-delete")
        }
    }
}

/// Edits one set: weight, reps and type; can also remove it.
private struct SetEditSheet: View {
    let edit: WorkoutDetailView.SetEdit
    let unitSymbol: String
    let save: (String, String, SetType) async -> Void
    let delete: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight: String
    @State private var reps: String
    @State private var type: SetType

    init(
        edit: WorkoutDetailView.SetEdit, unitSymbol: String, save: @escaping (String, String, SetType) async -> Void,
        delete: @escaping () async -> Void
    ) {
        self.edit = edit
        self.unitSymbol = unitSymbol
        self.save = save
        self.delete = delete
        _weight = State(initialValue: edit.weightText)
        _reps = State(initialValue: edit.repsText)
        _type = State(initialValue: edit.type)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("history.set.weight \(unitSymbol)")
                    TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("history-set-weight")
                }
                HStack {
                    Text("history.set.reps")
                    TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("history-set-reps")
                }
                Picker("history.set.type", selection: $type) {
                    Text("history.set.type.working").tag(SetType.working)
                    Text("history.set.type.warmup").tag(SetType.warmup)
                    Text("history.set.type.drop").tag(SetType.drop)
                    Text("history.set.type.failure").tag(SetType.failure)
                }
                Button("history.delete", role: .destructive) { Task { await delete() } }
            }
            .navigationTitle("history.set.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("workout.cancel.keep") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("workout.note.save") { Task { await save(weight, reps, type) } }
                        .accessibilityIdentifier("history-set-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
