import DataKit
import DesignSystem
import SwiftUI

/// One program (P033): name, active choice, days, weekly plan and the live weekly set count per muscle.
struct RoutineEditorView: View {
    let routineId: UUID
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: RoutineEditorModel?
    @State private var failed = false
    @State private var name = ""
    @State private var addingDay = false
    @State private var newDayName = ""
    @State private var editMode: EditMode = .inactive
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
        .navigationTitle("routine.editor.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("routine-editor-root")
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
        name = made.routine?.name ?? ""
    }

    @ViewBuilder
    private func content(_ model: RoutineEditorModel) -> some View {
        switch model.loadState {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "routine.error.load") { Task { await model.load() } }
        case .missing:
            EmptyState(systemImage: "questionmark.circle", title: "routine.missing.title", message: "routine.missing.message")
        case .loaded:
            if let routine = model.routine { editor(routine, model: model) }
        }
    }

    private func editor(_ routine: RoutineSnapshot, model: RoutineEditorModel) -> some View {
        List {
            Section {
                TextField("routine.new.namePrompt", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitName(model) }
                    .accessibilityIdentifier("routine-name-field")
                Toggle("routine.editor.active", isOn: Binding(get: { model.isActive }, set: { model.setActive($0) }))
                    .accessibilityIdentifier("routine-active-toggle")
            } footer: {
                Text("routine.editor.active.footer")
            }
            if !model.emptyDays.isEmpty {
                Section {
                    ForEach(model.emptyDays) { day in
                        Label("routine.warning.emptyDay \(day.name)", systemImage: "exclamationmark.triangle.fill")
                            .font(DSFont.callout).foregroundStyle(DSColor.warning)
                    }
                }
                .accessibilityIdentifier("routine-empty-day-warning")
            }
            daysSection(routine, model: model)
            weekSection(routine, model: model)
            volumeSection(model)
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
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
        }
        .alert("routine.day.newTitle", isPresented: $addingDay) {
            TextField("routine.day.namePrompt", text: $newDayName)
            Button("routine.action.cancel", role: .cancel) {}
            Button("routine.day.add") { addDay(model, routine: routine) }
        }
        .alert("routine.error.save", isPresented: Bindable(model).errorOccurred) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName(model) } }
        .onDisappear { commitName(model) }
        .onAppear { Task { await model.load() } }
    }

    // MARK: Sections

    private func daysSection(_ routine: RoutineSnapshot, model: RoutineEditorModel) -> some View {
        Section("routine.section.days") {
            ForEach(routine.days) { day in
                NavigationLink(value: WorkoutRoute.routineDay(routineId: routine.id, dayId: day.id)) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: day.name).font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                        if day.exercises.isEmpty {
                            Label("routine.day.empty", systemImage: "exclamationmark.triangle.fill")
                                .font(DSFont.caption).foregroundStyle(DSColor.warning)
                        } else {
                            Text("routine.day.exerciseCount \(day.exercises.count)")
                                .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
                .accessibilityIdentifier("routine-day-\(day.name)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await model.deleteDay(day.id) } } label: {
                        Label("routine.action.delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { Task { await model.duplicateDay(day.id, name: "\(day.name) 2") } } label: {
                        Label("routine.action.duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(DSColor.accent)
                }
            }
            .onMove { source, destination in Task { await model.moveDays(from: source, to: destination) } }
            Button {
                newDayName = ""
                addingDay = true
            } label: {
                Label("routine.day.add", systemImage: "plus")
            }
            .accessibilityIdentifier("routine-add-day")
        }
    }

    private func weekSection(_ routine: RoutineSnapshot, model: RoutineEditorModel) -> some View {
        Section {
            ForEach(weekdayOrder, id: \.self) { weekday in
                Picker(selection: Binding(
                    get: { model.weekdayPlan(weekday) },
                    set: { choice in
                        switch choice {
                        case .rest: model.assign(dayId: nil, toWeekday: weekday)
                        case .day(let id): model.assign(dayId: id, toWeekday: weekday)
                        case .elsewhere: break
                        }
                    }
                )) {
                    Text("routine.week.rest").tag(RoutineEditorModel.WeekdayPlan.rest)
                    ForEach(routine.days) { day in Text(verbatim: day.name).tag(RoutineEditorModel.WeekdayPlan.day(day.id)) }
                    if model.weekdayPlan(weekday) == .elsewhere {
                        Text("routine.week.elsewhere").tag(RoutineEditorModel.WeekdayPlan.elsewhere)
                    }
                } label: {
                    Text(verbatim: weekdayName(weekday))
                }
                .accessibilityIdentifier("routine-weekday-\(weekday)")
            }
        } header: {
            Text("routine.section.week")
        } footer: {
            Text("routine.week.footer")
        }
    }

    private func volumeSection(_ model: RoutineEditorModel) -> some View {
        Section {
            if model.weeklySets.isEmpty {
                Text("routine.volume.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            } else {
                let peak = model.weeklySets.map(\.sets).max() ?? 1
                ForEach(model.weeklySets) { count in
                    HStack(spacing: Spacing.sm) {
                        Text(verbatim: muscleName(count.muscle)).font(DSFont.callout).frame(width: 110, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(DSColor.accent)
                                .frame(width: max(4, proxy.size.width * count.sets / peak), height: 8)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        Text(verbatim: count.sets.formatted(.number.precision(.fractionLength(0...1))))
                            .font(DSFont.callout.monospacedDigit()).foregroundStyle(DSColor.textSecondary)
                            .frame(minWidth: 32, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("routine-volume-\(count.muscle)")
                }
            }
        } header: {
            Text("routine.section.volume")
        } footer: {
            Text("routine.volume.footer")
        }
    }

    // MARK: Helpers

    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.weekdaySymbols[weekday - 1]
    }

    private func muscleName(_ raw: String) -> String {
        Muscle(rawValue: raw)?.localizedName(locale: locale) ?? raw
    }

    private func commitName(_ model: RoutineEditorModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = model.routine?.name ?? ""
            return
        }
        Task { await model.rename(trimmed, notes: model.routine?.notes) }
    }

    private func addDay(_ model: RoutineEditorModel, routine: RoutineSnapshot) {
        let typed = newDayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayName = typed.isEmpty
            ? RoutineEditorModel.defaultDayName(routine.days.count + 1, languageCode: languageCode) : typed
        Task { _ = await model.addDay(name: dayName) }
    }
}
