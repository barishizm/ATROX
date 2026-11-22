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
    @State private var renaming = false

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
                header(day, model: model)
                analysisCard(day, model: model)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
            } header: {
                listHeader(day)
            }
            .listRowBackground(DSColor.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) { startBar(day) }
        .toolbar { toolbar(model, day: day) }
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
        .alert("routine.day.newTitle", isPresented: $renaming) {
            TextField("routine.day.namePrompt", text: $dayName)
            Button("routine.action.cancel", role: .cancel) { dayName = day.name }
            Button("routine.action.ok") { commitName(model) }
        }
        .alert("routine.error.save", isPresented: Bindable(model).errorOccurred) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .onChange(of: editMode) { _, mode in if !mode.isEditing { selection = [] } }
    }

    // MARK: Header, analysis, start

    private func header(_ day: RoutineDaySnapshot, model: RoutineEditorModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: day.name)
                .font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: Self.summary(day, locale: locale))
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md).padding(.top, Spacing.lg).padding(.bottom, Spacing.md)
        .accessibilityElement(children: .combine)
    }

    /// The muscles this day works, shaded by how many sets reach them.
    private func analysisCard(_ day: RoutineDaySnapshot, model: RoutineEditorModel) -> some View {
        let intensities = Self.muscleSets(of: day) { model.item(for: $0)?.primaryMuscles ?? [] }
        return HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("routine.day.analysis").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Text("routine.day.setsTotal").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                Text(verbatim: "\(day.exercises.reduce(0) { $0 + $1.input.targetSets })")
                    .font(DSFont.numericLarge).foregroundStyle(DSColor.textPrimary)
            }
            Spacer(minLength: 0)
            MuscleMapView(intensities: MuscleIntensities.heatmap(intensities), style: .default)
                .frame(height: 150)
        }
        .padding(Spacing.md)
        .background(DSColor.background, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(DSColor.separator))
        .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routine-day-analysis")
    }

    private func listHeader(_ day: RoutineDaySnapshot) -> some View {
        HStack {
            Text("routine.day.listSummary \(day.exercises.count) \(day.exercises.reduce(0) { $0 + $1.input.targetSets })")
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            Spacer()
            Button { picking = true } label: {
                Label("routine.day.addExercises", systemImage: "plus").labelStyle(.titleAndIcon)
                    .font(DSFont.callout.weight(.semibold))
                    .frame(minHeight: HitTarget.minimum)
            }
            .foregroundStyle(DSColor.accent)
            .accessibilityIdentifier("routine-add-exercise")
        }
        .textCase(nil)
    }

    private func startBar(_ day: RoutineDaySnapshot) -> some View {
        PrimaryButton("workout.start.day", systemImage: "play.circle") {
            Task { await presenter.start(routineId: routineId, dayId: dayId, container: container) }
        }
        .disabled(day.exercises.isEmpty)
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        .background(.bar)
        .accessibilityIdentifier("routine-day-start")
    }

    /// "6 exercises · 71 min"
    static func summary(_ day: RoutineDaySnapshot, locale: Locale) -> String {
        let count = String(localized: "routine.day.exerciseCount \(day.exercises.count)", locale: locale)
        let minutes = String(localized: "routine.day.minutes \(estimatedMinutes(day))", locale: locale)
        return "\(count) · \(minutes)"
    }

    /// About 45 s of work per set plus the rest between sets (90 s when a target has none).
    static func estimatedMinutes(_ day: RoutineDaySnapshot) -> Int {
        let seconds = day.exercises.reduce(0) { $0 + $1.input.targetSets * (45 + ($1.input.restSeconds ?? 90)) }
        return Int((Double(seconds) / 60).rounded())
    }

    /// Sets per muscle, counting each exercise's sets once for every primary muscle it trains.
    static func muscleSets(of day: RoutineDaySnapshot, muscles: (ExerciseRef) -> [String]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for exercise in day.exercises {
            for name in muscles(exercise.ref) {
                if let muscle = Muscle(rawValue: name) { result[muscle, default: 0] += Double(exercise.input.targetSets) }
            }
        }
        return result
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: RoutineEditorModel, day: RoutineDaySnapshot) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { dayName = day.name; renaming = true } label: { Image(systemName: "pencil") }
                .accessibilityLabel("routine.day.rename")
                .accessibilityIdentifier("routine-day-rename")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { editMode = editMode.isEditing ? .inactive : .active } label: {
                    Label(editMode.isEditing ? "routine.action.finishEdit" : "routine.action.reorder",
                          systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("routine-reorder")
                Button { Task { await model.undo() } } label: { Label("routine.action.undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("routine-undo")
            } label: {
                Image(systemName: "ellipsis").frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .accessibilityLabel("routine.action.more")
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
                .buttonStyle(.borderedProminent).tint(DSColor.accentFill)
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
                    .font(DSFont.headline).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                targetSummary(exercise.input)
                if let letter = model.supersetLetter(of: exercise, in: day), !joinsPrevious {
                    TagChip("routine.superset.badge \(letter)", style: .accent)
                }
            }
            Spacer(minLength: 0)
            if !editMode.isEditing {
                Button { editing = exercise } label: {
                    Image(systemName: "square.and.pencil").font(.title3).foregroundStyle(DSColor.textPrimary)
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("routine.action.edit")
                .accessibilityIdentifier("routine-exercise-menu-\(index)")
            }
        }
        .contentShape(Rectangle())
        .background {
            // A hidden link keeps the whole row tappable without the list's disclosure chevron.
            NavigationLink(value: WorkoutRoute.exerciseHistory(id: HistoryContext.id(of: exercise.ref))) { EmptyView() }
                .opacity(0)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.leading, group == nil ? 0 : Spacing.sm)
        .overlay(alignment: .leading) {
            if group != nil {
                Rectangle().fill(DSColor.accentFill).frame(width: 3)
                    .padding(.top, joinsPrevious ? 0 : Spacing.sm)
                    .padding(.bottom, joinsNext ? 0 : Spacing.sm)
                    .accessibilityHidden(true)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.md, bottom: 0, trailing: Spacing.sm))
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
        .accessibilityIdentifier("routine-exercise-\(index)")
    }

    /// "3 sets · 5 reps · 2.0 RiR"; the short form (numbers only) when the row is too narrow.
    private func targetSummary(_ input: RoutineExerciseInput) -> some View {
        let reps = Self.repsText(input)
        let rir = input.targetRir.map { Double($0).formatted(.number.precision(.fractionLength(1))) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                Label("routine.target.sets \(input.targetSets)", systemImage: "square.stack")
                if let reps { Label("routine.target.reps \(reps)", systemImage: "repeat") }
                if let rir { Label("routine.target.rir \(rir)", systemImage: "gauge.medium") }
            }
            HStack(spacing: Spacing.sm) {
                Label { Text(verbatim: "\(input.targetSets)") } icon: { Image(systemName: "square.stack") }
                if let reps { Label { Text(verbatim: reps) } icon: { Image(systemName: "repeat") } }
                if let rir { Label { Text(verbatim: rir) } icon: { Image(systemName: "gauge.medium") } }
            }
        }
        .labelStyle(.titleAndIcon)
        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
        .lineLimit(1)
    }

    static func repsText(_ input: RoutineExerciseInput) -> String? {
        switch (input.targetRepsMin, input.targetRepsMax) {
        case let (low?, high?): low == high ? "\(low)" : "\(low)–\(high)"
        case let (low?, nil): "\(low)+"
        case let (nil, high?): "≤\(high)"
        case (nil, nil): nil
        }
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
