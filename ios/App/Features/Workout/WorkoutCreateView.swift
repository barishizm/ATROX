import DataKit
import DesignSystem
import SwiftUI

/// "Create": the one place that starts anything new from the Workout tab: a program from scratch, a program from a
/// template, or a one-off workout without a program.
struct WorkoutCreateView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @Environment(\.locale) private var locale
    @State private var model: RoutineListModel?
    @State private var naming = false
    @State private var newName = ""
    @State private var opened: UUID?
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("workout.create.subtitle")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .padding(.bottom, Spacing.xs)
                option(
                    "workout.create.scratch.title", "workout.create.scratch.message", icon: "square.and.pencil", id: "create-scratch"
                ) {
                    newName = ""
                    naming = true
                }
                NavigationLink(value: WorkoutRoute.templates) {
                    optionLabel("workout.create.template.title", "workout.create.template.message", icon: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("create-template")
                option(
                    "workout.start.empty", "workout.create.quick.message", icon: "bolt.fill", id: "create-quick-workout"
                ) {
                    Task { await presenter.startEmpty(container: container) }
                }
            }
            .padding(Spacing.md)
        }
        .background(DSColor.background)
        .navigationTitle("workout.create.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { model = await container.makeRoutineListModel() }
        .navigationDestination(item: $opened) { RoutineEditorView(routineId: $0) }
        .alert("routine.new.title", isPresented: $naming) {
            TextField("routine.new.namePrompt", text: $newName)
            Button("routine.action.cancel", role: .cancel) {}
            Button("routine.new.create") { create() }
        }
        .alert("routine.error.save", isPresented: $saveFailed) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .accessibilityIdentifier("workout-create-root")
    }

    private func option(
        _ title: LocalizedStringKey, _ message: LocalizedStringKey, icon: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            optionLabel(title, message, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func optionLabel(_ title: LocalizedStringKey, _ message: LocalizedStringKey, icon: String) -> some View {
        Card(padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(.title3, weight: .semibold)).foregroundStyle(DSColor.accent)
                    .frame(width: 52, height: 52)
                    .background(DSColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text(message)
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right").font(DSFont.callout).foregroundStyle(DSColor.textTertiary)
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let model else { return }
        let code = locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
        Task {
            if let id = await model.create(name: name, firstDayName: RoutineEditorModel.defaultDayName(1, languageCode: code)) {
                opened = id
            } else {
                saveFailed = true
            }
        }
    }
}
