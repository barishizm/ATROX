import DesignSystem
import SwiftUI

struct WorkoutRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter

    var body: some View {
        VStack(spacing: Spacing.lg) {
            FeaturePlaceholderView(title: "shell.tabbar.workout", systemImage: "dumbbell")
            if presenter.hasActiveWorkout {
                Button { presenter.resume() } label: { Label("workout.continue", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("continue-workout")
            } else {
                Button { Task { await presenter.startEmpty(container: container) } } label: {
                    Label("workout.start.empty", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("start-empty-workout")
            }
            NavigationLink(value: WorkoutRoute.routines) {
                Label("routine.list.title", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("open-routines")
            NavigationLink(value: WorkoutRoute.exerciseLibrary) {
                Label("library.exercises.title", systemImage: "books.vertical")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("open-exercise-library")
        }
        .navigationTitle("shell.tabbar.workout")
    }
}
