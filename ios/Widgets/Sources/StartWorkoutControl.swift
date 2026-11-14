import AppIntents
import SwiftUI
import WidgetKit

/// "Start workout" for Control Center, the Lock Screen and the Action Button (P096).
struct StartWorkoutControl: ControlWidget {
    static let kind = "ATROXStartWorkoutControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("control.start.label", systemImage: "dumbbell.fill")
            }
        }
        .displayName("control.start.name")
        .description("control.start.description")
    }
}
