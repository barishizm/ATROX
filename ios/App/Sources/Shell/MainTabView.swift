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

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                NavigationStack(path: $today.path) {
                    TodayRootView()
                        .navigationDestination(for: TodayRoute.self) { _ in
                            FeaturePlaceholderView(title: "shell.tabbar.today", systemImage: "sun.max")
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
                            case .activeWorkout: FeaturePlaceholderView(title: "shell.tabbar.workout", systemImage: "dumbbell")
                            }
                        }
                }
            }
            Tab(AppTab.analysis.title, systemImage: AppTab.analysis.systemImage, value: AppTab.analysis) {
                NavigationStack(path: $analysis.path) {
                    AnalysisRootView()
                        .navigationDestination(for: AnalysisRoute.self) { _ in
                            FeaturePlaceholderView(title: "shell.tabbar.analysis", systemImage: "chart.line.uptrend.xyaxis")
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
        .tabViewBottomAccessory {
            if let model = workoutPresenter.model, model.isActive, !workoutPresenter.isPresented {
                MiniWorkoutBar(model: model) { workoutPresenter.resume() }
            }
        }
        .environment(workoutPresenter)
        .task { await workoutPresenter.prepare(container: container) }
        .fullScreenCover(isPresented: $workoutPresenter.isPresented) {
            if let model = workoutPresenter.model {
                ActiveWorkoutView(model: model, presenter: workoutPresenter)
                    .environment(container)
            }
        }
        .accessibilityIdentifier("main-tabs")
    }
}
