import DataKit
import DesignSystem
import SwiftUI

/// The Workout tab. Without a program it offers one thing: create. With programs it lists them (the active one is
/// marked) and offers to continue a running workout. Below sits the 0–100 score of everything trained so far.
struct WorkoutRootView: View {
    let router: TabRouter<WorkoutRoute>
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @State private var model: RoutineListModel?
    @State private var failed = false

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
        .navigationTitle("shell.tabbar.workout")
        .task { await prepare() }
    }

    /// Builds the model once; coming back to the tab only reloads it, so state such as the undo bar survives.
    private func prepare() async {
        if let model {
            await model.load()
            return
        }
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
        switch model.loadState {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "routine.error.load") { Task { await model.load() } }
        case .loaded:
            if model.routines.isEmpty { emptyHero } else { home(model) }
        }
    }

    // MARK: - No program yet

    private var emptyHero: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(DSColor.accent.opacity(0.07)).frame(width: 190, height: 190)
                Circle().fill(DSColor.accent.opacity(0.13)).frame(width: 138, height: 138)
                Circle().fill(DSColor.accentFill).frame(width: 92, height: 92)
                    .dsShadow(.raised)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(DSColor.onAccent)
                    .rotationEffect(.degrees(-35))
            }
            .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text("workout.empty.title")
                    .font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("workout.empty.message")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.md)
            PrimaryButton("workout.create.button", systemImage: "plus") { router.push(.create) }
                .padding(.horizontal, Spacing.xl)
                .accessibilityIdentifier("workout-create")
            TodayRootView().padding(.horizontal, Spacing.md)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Has programs

    private func home(_ model: RoutineListModel) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if presenter.hasActiveWorkout {
                    PrimaryButton("workout.continue", systemImage: "play.fill") { presenter.resume() }
                        .accessibilityIdentifier("continue-workout")
                }
                ForEach(model.routines) { routine in
                    programCard(routine, model: model)
                }
                TodayRootView()
            }
            .padding(Spacing.md)
        }
        .safeAreaInset(edge: .bottom) { if model.lastDeleted != nil { undoBar(model) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.create) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("workout.create.button")
                    .accessibilityIdentifier("workout-create")
            }
        }
    }

    private func programCard(_ routine: RoutineSnapshot, model: RoutineListModel) -> some View {
        let isActive = model.plan.activeRoutineId == routine.id
        return Card {
            HStack(spacing: Spacing.sm) {
                NavigationLink(value: Self.destination(of: routine)) {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if isActive { TagChip("routine.badge.active", style: .accent) }
                            Text(verbatim: routine.name)
                                .font(DSFont.title).foregroundStyle(DSColor.textPrimary).multilineTextAlignment(.leading)
                            Group {
                                if routine.days.count == 1 {
                                    Text("routine.day.exerciseCount \(routine.exerciseCount)")
                                } else {
                                    Text("routine.summary \(routine.days.count) \(routine.exerciseCount)")
                                }
                            }
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer(minLength: Spacing.sm)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button { model.setActive(routine.id) } label: {
                        Label("routine.action.setActive", systemImage: "checkmark.circle")
                    }
                    Button { Task { await model.duplicate(routine.id, name: "\(routine.name) 2") } } label: {
                        Label("routine.action.duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) { Task { await model.delete(routine.id) } } label: {
                        Label("routine.action.delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(.body, weight: .semibold)).foregroundStyle(DSColor.textSecondary)
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                }
                .accessibilityLabel("routine.action.more")
                .accessibilityIdentifier("program-menu-\(routine.name)")
            }
        }
        .accessibilityIdentifier("program-card-\(routine.name)")
    }

    /// A one-day program opens its day (the exercise list with Start Workout); a longer one opens the program.
    static func destination(of routine: RoutineSnapshot) -> WorkoutRoute {
        if routine.days.count == 1, let day = routine.days.first { return .routineDay(routineId: routine.id, dayId: day.id) }
        return .routine(id: routine.id)
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
}
