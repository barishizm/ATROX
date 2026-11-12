import DesignSystem
import SwiftUI

struct WorkoutRootView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            FeaturePlaceholderView(title: "shell.tabbar.workout", systemImage: "dumbbell")
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
