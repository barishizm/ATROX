import SwiftUI

/// The five-tab shell. Each tab owns a `NavigationStack` driven by its typed route enum.
struct MainTabView: View {
    @State private var selection: AppTab = .today
    @State private var today = TabRouter<TodayRoute>()
    @State private var workout = TabRouter<WorkoutRoute>()
    @State private var analysis = TabRouter<AnalysisRoute>()
    @State private var coach = TabRouter<CoachRoute>()
    @State private var profile = TabRouter<ProfileRoute>()
    @State private var workoutPresenter = ActiveWorkoutPresenter()
    @Environment(AppContainer.self) private var container

    private var showsMiniBar: Bool {
        guard let model = workoutPresenter.model else { return false }
        return model.isActive && !workoutPresenter.isPresented
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                NavigationStack(path: $today.path) {
                    TodayRootView()
                        .navigationDestination(for: TodayRoute.self) { route in
                            switch route {
                            case .workoutSummary: FeaturePlaceholderView(title: "shell.tabbar.today", systemImage: "sun.max")
                            case .exerciseScore(let id): ExerciseScoreView(exerciseID: id)
                            case .templates: TemplateListView()
                            case .weeklySummary: WeeklySummaryView()
                            }
                        }
                }
            }
            Tab(AppTab.workout.title, systemImage: AppTab.workout.systemImage, value: AppTab.workout) {
                NavigationStack(path: $workout.path) {
                    WorkoutRootView()
                        .navigationDestination(for: WorkoutRoute.self) { route in
                            switch route {
                            case .exerciseLibrary: LibraryView()
                            case .exerciseDetail(let id): ExerciseDetailView(exerciseID: id)
                            case .routines: RoutineListView()
                            case .templates: TemplateListView()
                            case .routine(let id): RoutineEditorView(routineId: id)
                            case .routineDay(let routineId, let dayId): RoutineDayView(routineId: routineId, dayId: dayId)
                            case .history: HistoryView()
                            case .workoutDetail(let id): WorkoutDetailView(workoutId: id)
                            case .exerciseHistory(let id): ExerciseHistoryView(exerciseID: id)
                            case .activeWorkout: FeaturePlaceholderView(title: "shell.tabbar.workout", systemImage: "dumbbell")
                            }
                        }
                }
            }
            Tab(AppTab.analysis.title, systemImage: AppTab.analysis.systemImage, value: AppTab.analysis) {
                NavigationStack(path: $analysis.path) {
                    AnalysisRootView(router: analysis)
                        .navigationDestination(for: AnalysisRoute.self) { route in
                            switch route {
                            case .muscle(let name): MuscleDetailView(muscleName: name)
                            case .exerciseScore(let id): ExerciseScoreView(exerciseID: id)
                            case .exerciseDetail(let id): ExerciseDetailView(exerciseID: id)
                            }
                        }
                }
            }
            Tab(AppTab.coach.title, systemImage: AppTab.coach.systemImage, value: AppTab.coach) {
                NavigationStack(path: $coach.path) {
                    CoachRootView()
                        .navigationDestination(for: CoachRoute.self) { _ in
                            FeaturePlaceholderView(title: "shell.tabbar.coach", systemImage: "bubble.left.and.text.bubble.right")
                        }
                }
            }
            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                ProfileTabView(router: profile)
            }
        }
        .modifier(MiniBarAccessory(isEnabled: showsMiniBar) {
            if let model = workoutPresenter.model, model.isActive, !workoutPresenter.isPresented {
                MiniWorkoutBar(model: model) { workoutPresenter.resume() }
            }
        })
        .environment(workoutPresenter)
        .onChange(of: container.requestedTab) { _, tab in
            guard let tab else { return }
            selection = tab
            container.requestedTab = nil
        }
        .onChange(of: container.deepLinks.pending, initial: true) { _, pending in
            guard pending != nil, let link = container.deepLinks.consume() else { return }
            open(link)
        }
        .onChange(of: container.requestedRoutine, initial: true) { _, id in
            guard let id else { return }
            container.requestedRoutine = nil
            selection = .workout
            workout.popToRoot()
            workout.push(.routine(id: id))
        }
        .task { await workoutPresenter.prepare(container: container) }
        .fullScreenCover(isPresented: $workoutPresenter.isPresented) {
            if let summary = workoutPresenter.summary {
                WorkoutSummaryView(model: summary) { workoutPresenter.summaryDone() }
            } else if let model = workoutPresenter.model {
                ActiveWorkoutView(model: model, presenter: workoutPresenter)
                    .environment(container)
            }
        }
        .accessibilityIdentifier("main-tabs")
    }

    /// Opens a deep link in the right tab (P088).
    private func open(_ link: DeepLink) {
        switch link {
        case .tab(let tab): selection = tab
        case .weeklySummary:
            selection = .today
            today.popToRoot()
            today.push(.weeklySummary)
        case .startWorkout(let routineId, let dayId):
            selection = .workout
            Task { await workoutPresenter.start(routineId: routineId, dayId: dayId, container: container) }
        case .friendInvite(let username):
            selection = .profile
            profile.popToRoot()
            profile.push(.social)
            profile.push(.invite(username: username))
        }
    }
}

/// Hides the bottom accessory entirely when there is nothing to show (iOS 26.1+);
/// on 26.0 the accessory API has no way to be disabled, so it stays as before.
private struct MiniBarAccessory<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder let accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled, content: accessory)
        } else {
            content.tabViewBottomAccessory(content: accessory)
        }
    }
}
