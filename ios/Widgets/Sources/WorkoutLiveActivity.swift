import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island layouts of the workout Live Activity (P038).
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(LiveStyle.background)
                .activitySystemActionForegroundColor(LiveStyle.accent)
        } dynamicIsland: { context in
            let rest = RestWindow(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExerciseLabel(state: context.state).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingClock(attributes: context.attributes, state: context.state, rest: rest)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if rest != nil {
                        RestRow()
                    } else if context.state.isFinished {
                        Text(verbatim: summary(context.state)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: rest == nil ? "dumbbell.fill" : "timer").foregroundStyle(LiveStyle.accent)
            } compactTrailing: {
                CompactClock(attributes: context.attributes, state: context.state, rest: rest)
            } minimal: {
                Image(systemName: rest == nil ? "dumbbell.fill" : "timer").foregroundStyle(LiveStyle.accent)
            }
            .keylineTint(LiveStyle.accent)
        }
    }
}

// MARK: Style

enum LiveStyle {
    /// Same lime as `DSColor.accent` on the dark palette; the extension does not link DesignSystem.
    static let accent = Color(red: 198 / 255, green: 241 / 255, blue: 53 / 255)
    static let background = Color(red: 10 / 255, green: 12 / 255, blue: 15 / 255)
}

// MARK: Content

/// The rest countdown if one is running and has not run out.
struct RestWindow {
    let start: Date
    let end: Date

    init?(state: WorkoutActivityAttributes.ContentState, isStale: Bool, now: Date = .now) {
        guard !isStale, !state.isFinished, let start = state.restStart, let end = state.restEnd, end > now, end > start
        else { return nil }
        self.start = start
        self.end = end
    }

    var range: ClosedRange<Date> { start...end }
}

private func summary(_ state: WorkoutActivityAttributes.ContentState) -> String {
    String(localized: "liveactivity.summary \(state.completedSets)")
}

private func duration(from start: Date, to end: Date) -> String {
    Duration.seconds(max(0, end.timeIntervalSince(start))).formatted(.time(pattern: .hourMinuteSecond))
}

private struct ExerciseLabel: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isFinished {
            Text("liveactivity.finished").font(.headline).foregroundStyle(LiveStyle.accent)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: state.exerciseName).font(.headline).lineLimit(1)
                Text(verbatim: "\(state.setNumber)/\(state.setCount)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// Elapsed workout time, or the final duration once it is over.
private struct ElapsedClock: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let endedAt = state.endedAt {
            Text(verbatim: duration(from: attributes.startedAt, to: endedAt)).monospacedDigit()
        } else {
            Text(attributes.startedAt, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

private struct TrailingClock: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let rest: RestWindow?

    var body: some View {
        if let rest {
            Text(timerInterval: rest.range, countsDown: true, showsHours: false)
                .font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(LiveStyle.accent)
                .multilineTextAlignment(.trailing)
        } else {
            ElapsedClock(attributes: attributes, state: state).font(.title3)
        }
    }
}

private struct CompactClock: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let rest: RestWindow?

    var body: some View {
        if let rest {
            Text(timerInterval: rest.range, countsDown: true, showsHours: false)
                .monospacedDigit().foregroundStyle(LiveStyle.accent).frame(maxWidth: 48)
        } else if let endedAt = state.endedAt {
            Text(verbatim: duration(from: attributes.startedAt, to: endedAt)).monospacedDigit().frame(maxWidth: 56)
        } else {
            Text(attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 56)
        }
    }
}

private struct RestRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Button(intent: SkipRestIntent()) { Text("liveactivity.skip").frame(maxWidth: .infinity) }
                .tint(LiveStyle.accent)
            Button(intent: ExtendRestIntent()) { Text("liveactivity.extend").frame(maxWidth: .infinity) }
                .tint(LiveStyle.accent)
        }
        .buttonStyle(.bordered)
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let rest = RestWindow(state: state, isStale: isStale)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: attributes.workoutName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    ExerciseLabel(state: state)
                }
                Spacer(minLength: 8)
                if let rest {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("liveactivity.rest").font(.caption).foregroundStyle(.secondary)
                        Text(timerInterval: rest.range, countsDown: true, showsHours: false)
                            .font(.title.monospacedDigit().weight(.bold)).foregroundStyle(LiveStyle.accent)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        if state.isFinished {
                            Text(verbatim: summary(state)).font(.caption).foregroundStyle(.secondary)
                        }
                        ElapsedClock(attributes: attributes, state: state).font(.title2.weight(.semibold))
                    }
                }
            }
            if rest != nil { RestRow() }
        }
        .foregroundStyle(.white)
    }
}
