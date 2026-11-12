import DataKit
import DesignSystem
import SwiftUI

/// The user's programs (P033): open, create, duplicate, delete (undoable) and pick the active one.
struct RoutineListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: RoutineListModel?
    @State private var failed = false
    @State private var naming = false
    @State private var newName = ""
    @State private var opened: UUID?

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
        .navigationTitle("routine.list.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("routine-list-root")
    }

    private func prepare() async {
        failed = false
        if let made = await container.makeRoutineListModel() {
            model = made
            await made.load()
        } else {
            failed = true
        }
    }

    @ViewBuilder
    private func content(_ model: RoutineListModel) -> some View {
        Group {
            switch model.loadState {
            case .loading: LoadingState()
            case .failed: ErrorState(message: "routine.error.load") { Task { await model.load() } }
            case .loaded:
                if model.routines.isEmpty { emptyState } else { list(model) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { startNaming() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("routine.list.new")
                    .accessibilityIdentifier("routine-add")
            }
        }
        .safeAreaInset(edge: .bottom) { if model.lastDeleted != nil { undoBar(model) } }
        .alert("routine.new.title", isPresented: $naming) {
            TextField("routine.new.namePrompt", text: $newName)
            Button("routine.action.cancel", role: .cancel) {}
            Button("routine.new.create") { create(model) }
        }
        .alert("routine.error.save", isPresented: Bindable(model).errorOccurred) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .navigationDestination(item: $opened) { RoutineEditorView(routineId: $0) }
        .onAppear { Task { await model.load() } }
    }

    private var emptyState: some View {
        EmptyState(
            systemImage: "list.bullet.rectangle", title: "routine.list.empty.title",
            message: "routine.list.empty.message", actionTitle: "routine.list.new", action: startNaming
        )
    }

    private func list(_ model: RoutineListModel) -> some View {
        List {
            ForEach(model.routines) { routine in
                NavigationLink(value: WorkoutRoute.routine(id: routine.id)) { row(routine, model: model) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.delete(routine.id) } } label: {
                            Label("routine.action.delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { Task { await model.duplicate(routine.id, name: "\(routine.name) 2") } } label: {
                            Label("routine.action.duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(DSColor.accent)
                    }
                    .contextMenu {
                        Button { model.setActive(routine.id) } label: {
                            Label("routine.action.setActive", systemImage: "checkmark.circle")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ routine: RoutineSnapshot, model: RoutineListModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: routine.name).font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                Text("routine.summary \(routine.days.count) \(routine.exerciseCount)")
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            if model.plan.activeRoutineId == routine.id { TagChip("routine.badge.active", style: .accent) }
        }
        .accessibilityIdentifier("routine-row-\(routine.name)")
    }

    private func undoBar(_ model: RoutineListModel) -> some View {
        HStack {
            Text("routine.deleted.message").font(DSFont.callout)
            Spacer()
            Button("routine.action.undo") { Task { await model.undoDelete() } }
                .font(DSFont.callout.weight(.semibold))
                .accessibilityIdentifier("routine-undo-delete")
        }
        .padding(Spacing.md)
        .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Spacing.md)
        .task(id: model.lastDeleted?.id) {
            try? await Task.sleep(for: .seconds(6))
            model.dismissUndo()
        }
    }

    private func startNaming() {
        newName = ""
        naming = true
    }

    private func create(_ model: RoutineListModel) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let code = locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
        Task {
            if let id = await model.create(name: name, firstDayName: RoutineEditorModel.defaultDayName(1, languageCode: code)) {
                opened = id
            }
        }
    }
}
