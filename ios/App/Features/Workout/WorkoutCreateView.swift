import DataKit
import DesignSystem
import SwiftUI

/// "Create": the one place that starts anything new from the Workout tab: a program from scratch, a program from a
/// template, or a one-off workout without a program.
struct WorkoutCreateView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @State private var settingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("workout.create.subtitle")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .padding(.bottom, Spacing.xs)
                option(
                    "workout.create.scratch.title", "workout.create.scratch.message", icon: "square.and.pencil", id: "create-scratch"
                ) {
                    settingUp = true
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
        .sheet(isPresented: $settingUp) {
            ProgramSetupSheet(source: .scratch)
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
}
