import DataKit
import DesignSystem
import SwiftUI

/// The active workout screen (P036), built for one hand in the gym: pre-filled sets finish with one tap, numbers
/// come from a custom keypad, and the whole screen can be minimized while the workout keeps running.
struct ActiveWorkoutView: View {
    let model: ActiveWorkoutModel
    let presenter: ActiveWorkoutPresenter
    @AppStorage(WorkoutPreferences.keepAwakeKey) private var keepAwake = true
    @AppStorage(WorkoutPreferences.showRirKey) private var showsRir = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsFinish = false
    @State private var confirmsCancel = false
    @State private var adding = false
    @State private var replacing: ActiveWorkoutModel.ExerciseCard?
    @State private var noting: ActiveWorkoutModel.ExerciseCard?
    @State private var noteText = ""
    @State private var history: ActiveWorkoutModel.ExerciseCard?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.cards) { card in
                    Section {
                        ForEach(card.rows) { row in
                            setRow(row, card: card)
                                .listRowInsets(EdgeInsets(top: 2, leading: Spacing.md, bottom: 2, trailing: Spacing.md))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await model.removeSet(row.id) }
                                    } label: { Label("workout.set.delete", systemImage: "trash") }
                                }
                        }
                        Button { Task { await model.addSet(to: card.id) } } label: {
                            Label("workout.set.add", systemImage: "plus")
                        }
                        .accessibilityIdentifier("workout-add-set")
                    } header: {
                        header(card)
                    }
                }
                Section {
                    Button { adding = true } label: { Label("workout.exercise.add", systemImage: "plus.circle.fill") }
                        .accessibilityIdentifier("workout-add-exercise")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DSColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    RestTimerView(timer: model.rest)
                    if let editing = model.editing { WorkoutKeypadView(model: model, editing: editing) }
                }
            }
            .navigationDestination(for: WorkoutRoute.self) { route in
                if case .exerciseDetail(let id) = route { ExerciseDetailView(exerciseID: id) }
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) {
            Task { await model.rest.scenePhaseChanged(active: scenePhase == .active) }
        }
        .sheet(isPresented: Binding(
            get: { model.rest.showsPermissionPrimer }, set: { if !$0 { model.rest.declinePrimer() } }
        )) { RestNotificationPrimerView(timer: model.rest) }
        .onAppear { applyKeepAwake() }
        .onChange(of: keepAwake) { applyKeepAwake() }
        .onDisappear { WorkoutPreferences.setIdleTimerDisabled(false) }
        .confirmationDialog("workout.finish.confirm", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("workout.finish.action") {
                Task {
                    if await model.finish() != nil { presenter.ended() }
                }
            }
        } message: {
            Text("workout.finish.message \(model.completedSetCount) \(model.totalSetCount)")
        }
        .confirmationDialog("workout.cancel.confirm", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("workout.cancel.action", role: .destructive) {
                Task {
                    await model.cancel()
                    presenter.ended()
                }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                LibraryView(onAdd: { ids in
                    adding = false
                    Task {
                        for id in ids { await model.addExercise(Self.ref(id)) }
                    }
                })
            }
        }
        .sheet(item: $replacing) { card in replaceSheet(card) }
        .sheet(item: $history) { card in historySheet(card) }
        .alert("workout.note.title", isPresented: Binding(get: { noting != nil }, set: { if !$0 { noting = nil } })) {
            TextField("workout.note.placeholder", text: $noteText)
            Button("workout.note.save") {
                if let card = noting { Task { await model.setNotes(card.id, noteText) } }
                noting = nil
            }
            Button("workout.cancel.keep", role: .cancel) { noting = nil }
        }
        .alert("workout.error.title", isPresented: Binding(get: { model.errorKey != nil }, set: { if !$0 { model.errorKey = nil } })) {
            Button("workout.ok", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(model.errorKey ?? "workout.error.generic"))
        }
        .accessibilityIdentifier("active-workout-root")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { presenter.isPresented = false } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("workout.minimize")
                .accessibilityIdentifier("workout-minimize")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Group {
                    if model.title.isEmpty { Text("workout.title.default") } else { Text(verbatim: model.title) }
                }
                .font(DSFont.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: ActiveWorkoutFormat.clock(model.session.elapsed(at: context.date)))
                        .font(DSFont.caption).monospacedDigit().foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("workout-elapsed")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle("settings.workout.keepAwake", isOn: $keepAwake)
                Button("workout.cancel.action", role: .destructive) { confirmsCancel = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("workout.more")
                .accessibilityIdentifier("workout-more")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("workout.finish.action") { confirmsFinish = true }
                .fontWeight(.semibold)
                .accessibilityIdentifier("workout-finish")
        }
    }

    // MARK: Exercise header

    private func header(_ card: ActiveWorkoutModel.ExerciseCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                if card.supersetGroup != nil {
                    Image(systemName: "link").foregroundStyle(DSColor.accent).accessibilityLabel("workout.superset")
                }
                Text(verbatim: card.name).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    .textCase(nil)
                Spacer()
                Menu {
                    NavigationLink(value: WorkoutRoute.exerciseDetail(id: ActiveWorkoutModel.id(of: card.ref))) {
                        Label("workout.exercise.detail", systemImage: "info.circle")
                    }
                    Button { history = card } label: { Label("workout.exercise.history", systemImage: "clock.arrow.circlepath") }
                    Button { replacing = card } label: { Label("workout.exercise.replace", systemImage: "arrow.triangle.2.circlepath") }
                    Button {
                        noteText = card.notes ?? ""
                        noting = card
                    } label: { Label("workout.exercise.note", systemImage: "note.text") }
                    Button(role: .destructive) { Task { await model.removeExercise(card.id) } } label: {
                        Label("workout.exercise.remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: HitTarget.minimum, height: HitTarget.minimum)
                }
                .accessibilityLabel("workout.exercise.menu")
                .accessibilityIdentifier("workout-exercise-menu")
            }
            if let notes = card.notes {
                Text(verbatim: notes).font(DSFont.caption).foregroundStyle(DSColor.textSecondary).textCase(nil)
            }
            columnHeads
        }
    }

    private var columnHeads: some View {
        HStack(spacing: Spacing.sm) {
            Text("workout.col.set").frame(width: 44)
            Text("workout.col.previous").frame(maxWidth: .infinity)
            Text(verbatim: model.unit.symbol.uppercased()).frame(width: 72)
            Text("workout.col.reps").frame(width: 56)
            if showsRir { Text("RIR").frame(width: 44) }
            Color.clear.frame(width: HitTarget.button)
        }
        .font(DSFont.overline).foregroundStyle(DSColor.textTertiary).textCase(nil)
    }

    // MARK: Set row

    private func setRow(_ row: ActiveWorkoutModel.SetRow, card: ActiveWorkoutModel.ExerciseCard) -> some View {
        let editingWeight = model.editing?.setId == row.id && model.editing?.keypad.field == .weight
        let editingReps = model.editing?.setId == row.id && model.editing?.keypad.field == .reps
        let tint = row.isCompleted ? DSColor.textPrimary : DSColor.textSecondary
        return HStack(spacing: Spacing.sm) {
            typeMenu(row)
            Text(verbatim: row.previousText ?? "—")
                .font(DSFont.callout).foregroundStyle(DSColor.textTertiary).monospacedDigit()
                .frame(maxWidth: .infinity)
            field(editingWeight ? liveText(model.editing) : row.weightText, active: editingWeight, tint: tint, width: 72)
                .onTapGesture { Task { await model.beginEditing(row.id, field: .weight) } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("workout.field.weight \(model.unit.symbol)")
                .accessibilityValue(row.weightText)
                .accessibilityIdentifier("set-weight-\(card.rows.firstIndex(of: row) ?? 0)")
            field(editingReps ? liveText(model.editing) : row.repsText, active: editingReps, tint: tint, width: 56)
                .onTapGesture { Task { await model.beginEditing(row.id, field: .reps) } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("workout.field.reps")
                .accessibilityValue(row.repsText)
                .accessibilityIdentifier("set-reps-\(card.rows.firstIndex(of: row) ?? 0)")
            if showsRir { rirMenu(row) }
            Button {
                Haptics.play(row.isCompleted ? .light : .success)
                Task { await model.toggleComplete(row.id) }
            } label: {
                Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(row.isCompleted ? DSColor.success : DSColor.textTertiary)
                    .frame(width: HitTarget.button, height: HitTarget.button)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isCompleted ? "workout.set.undo" : "workout.set.complete")
            .accessibilityIdentifier("set-complete-\(card.rows.firstIndex(of: row) ?? 0)")
        }
        .frame(minHeight: HitTarget.button)
        .listRowBackground(row.isCompleted ? DSColor.success.opacity(0.12) : nil)
    }

    private func liveText(_ editing: ActiveWorkoutModel.Editing?) -> String {
        editing?.keypad.displayText(decimalSeparator: model.decimalSeparator) ?? ""
    }

    private func field(_ text: String, active: Bool, tint: Color, width: CGFloat) -> some View {
        Text(verbatim: text)
            .font(DSFont.numericMedium)
            .foregroundStyle(active ? DSColor.onAccent : tint)
            .frame(width: width, height: HitTarget.button - 8)
            .background(active ? DSColor.accent : DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(Rectangle())
    }

    private func typeMenu(_ row: ActiveWorkoutModel.SetRow) -> some View {
        Menu {
            ForEach(SetType.allCases, id: \.self) { type in
                Button { Task { await model.setType(row.id, type) } } label: {
                    if type == row.type { Label(Self.typeName(type), systemImage: "checkmark") } else { Text(Self.typeName(type)) }
                }
            }
        } label: {
            Text(verbatim: row.badge)
                .font(DSFont.headline)
                .foregroundStyle(row.type == .working ? DSColor.textPrimary : DSColor.accent)
                .frame(width: 44, height: HitTarget.minimum)
        }
        .accessibilityLabel("workout.set.type")
        .accessibilityIdentifier("set-type-\(row.badge)")
    }

    private func rirMenu(_ row: ActiveWorkoutModel.SetRow) -> some View {
        Menu {
            Button("workout.rir.none") { Task { await model.setRir(row.id, nil) } }
            ForEach(0...5, id: \.self) { value in
                Button(String(value)) { Task { await model.setRir(row.id, value) } }
            }
        } label: {
            Text(verbatim: row.rir.map(String.init) ?? "–")
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                .frame(width: 44, height: HitTarget.minimum)
        }
        .accessibilityLabel("RIR")
    }

    static func typeName(_ type: SetType) -> LocalizedStringKey {
        switch type {
        case .warmup: "workout.type.warmup"
        case .working: "workout.type.working"
        case .drop: "workout.type.drop"
        case .failure: "workout.type.failure"
        }
    }

    static func ref(_ id: String) -> ExerciseRef {
        UUID(uuidString: id).map(ExerciseRef.custom) ?? .catalog(id)
    }

    // MARK: Sheets

    private func replaceSheet(_ card: ActiveWorkoutModel.ExerciseCard) -> some View {
        let similar = model.similarExercises(to: card.ref)
        return NavigationStack {
            List {
                if !similar.isEmpty {
                    Section("workout.replace.similar") {
                        ForEach(similar) { item in
                            Button(item.name(languageCode: model.languageCode)) {
                                replacing = nil
                                Task { await model.replaceExercise(card.id, with: Self.ref(item.id)) }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("workout.replace.browse") {
                        LibraryView(onAdd: { ids in
                            replacing = nil
                            if let id = ids.first { Task { await model.replaceExercise(card.id, with: Self.ref(id)) } }
                        }, singleSelection: true)
                    }
                }
            }
            .navigationTitle("workout.exercise.replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("workout.cancel.keep") { replacing = nil } } }
        }
    }

    private func historySheet(_ card: ActiveWorkoutModel.ExerciseCard) -> some View {
        let last = model.session.previous[card.id] ?? []
        return NavigationStack {
            List {
                if last.isEmpty {
                    Text("workout.history.empty").foregroundStyle(DSColor.textSecondary)
                } else {
                    Section("workout.history.last") {
                        ForEach(Array(last.enumerated()), id: \.offset) { index, input in
                            HStack {
                                Text(verbatim: "\(index + 1)").foregroundStyle(DSColor.textSecondary)
                                Spacer()
                                Text(verbatim: "\(model.previousText(input)) \(model.unit.symbol)").monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: card.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("workout.ok") { history = nil } } }
        }
        .presentationDetents([.medium])
    }

    private func applyKeepAwake() { WorkoutPreferences.setIdleTimerDisabled(keepAwake) }
}
