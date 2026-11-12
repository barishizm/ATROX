import DesignSystem
import SwiftUI

/// Collapsed session bar shown above the tab bar while a workout runs and its screen is minimized.
struct MiniWorkoutBar: View {
    let model: ActiveWorkoutModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(DSColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("workout.mini.title").font(DSFont.callout)
                    Text("workout.mini.sets \(model.completedSetCount) \(model.totalSetCount)")
                        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: ActiveWorkoutFormat.clock(model.session.elapsed(at: context.date)))
                        .font(DSFont.headline).monospacedDigit()
                }
                Image(systemName: "chevron.up").foregroundStyle(DSColor.textSecondary).accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("workout.mini.open")
        .accessibilityIdentifier("workout-mini-bar")
    }
}

enum ActiveWorkoutFormat {
    /// "42:07" under an hour, "1:02:07" above.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
