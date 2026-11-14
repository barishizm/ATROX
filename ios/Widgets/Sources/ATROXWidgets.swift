import SwiftUI
import WidgetKit

// The three widgets of P096. Taps open the app through `widgetURL` (`atrox://…`, parsed by `DeepLink`).

private extension View {
    func atroxBackground() -> some View { containerBackground(LiveStyle.background, for: .widget) }
}

/// Header line used by the small and medium widgets.
private struct Caption: View {
    let key: LocalizedStringKey
    var body: some View {
        Text(key).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary).lineLimit(1)
    }
}

private struct Placeholder: View {
    let state: WidgetContentState
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: state == .signedOut ? "person.crop.circle.badge.questionmark" : "dumbbell").font(.title2)
                .foregroundStyle(LiveStyle.accent)
            Text(state == .signedOut ? "widget.state.signedout" : "widget.state.noscore")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Ring: View {
    let progress: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(progress, 0.001))
                .stroke(LiveStyle.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: Strength Score

struct ScoreWidget: Widget {
    static let kind = "ATROXScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            ScoreWidgetView(entry: entry)
                .widgetURL(WidgetLink.tab("analysis"))
                .atroxBackground()
        }
        .configurationDisplayName("widget.score.name")
        .description("widget.score.description")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ScoreWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let score = entry.snapshot?.score, entry.state == .ready {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Gauge(value: Double(score.value), in: 0...100) {
                        Text("widget.score.short")
                    } currentValueLabel: {
                        Text(verbatim: "\(score.value)").font(.title3.bold().monospacedDigit())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Caption(key: "widget.score.name")
                    ZStack {
                        Ring(progress: Double(score.value) / 100)
                        VStack(spacing: 0) {
                            Text(verbatim: "\(score.value)").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                .minimumScaleFactor(0.6).lineLimit(1)
                            if score.isProvisional {
                                Text("widget.score.provisional").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if let change = score.change, change != 0 {
                        Label {
                            Text(verbatim: change > 0 ? "+\(change)" : "\(change)").monospacedDigit()
                        } icon: {
                            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change > 0 ? LiveStyle.accent : Color.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .foregroundStyle(.white)
            }
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "gauge.with.dots.needle.0percent")
            }
        } else {
            Placeholder(state: entry.state).foregroundStyle(.white)
        }
    }
}

// MARK: Today's workout

struct TodayWorkoutWidget: Widget {
    static let kind = "ATROXTodayWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TodayWorkoutView(entry: entry)
                .widgetURL(entry.snapshot?.next.map { WidgetLink.startWorkout($0) } ?? WidgetLink.tab("workout"))
                .atroxBackground()
        }
        .configurationDisplayName("widget.today.name")
        .description("widget.today.description")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayWorkoutView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if entry.state == .signedOut {
                Placeholder(state: .signedOut)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Caption(key: entry.snapshot?.trainedToday == true ? "widget.today.done" : "widget.today.next")
                        if let day = entry.snapshot?.next {
                            Text(verbatim: day.dayName).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.8)
                            Text(verbatim: day.routineName).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            Text("widget.today.exercises \(day.exerciseCount)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("widget.today.noplan").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    VStack {
                        Spacer(minLength: 0)
                        Label("widget.today.start", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(LiveStyle.accentFill, in: Capsule())
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: Weekly goal and streak

struct WeeklyGoalWidget: Widget {
    static let kind = "ATROXWeeklyGoalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeeklyGoalView(entry: entry)
                .widgetURL(WidgetLink.tab("today"))
                .atroxBackground()
        }
        .configurationDisplayName("widget.weekly.name")
        .description("widget.weekly.description")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeeklyGoalView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let snapshot = entry.snapshot {
                    Gauge(value: entry.weeklyProgress) {
                        Image(systemName: "flame.fill")
                    } currentValueLabel: {
                        Text(verbatim: "\(entry.weeklyDone)/\(snapshot.weeklyGoal)").font(.caption.bold().monospacedDigit())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    Image(systemName: "flame")
                }
            }
        case .accessoryRectangular:
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text("widget.weekly.name").font(.caption2.weight(.semibold)).textCase(.uppercase)
                    Text("widget.weekly.progress \(entry.weeklyDone) \(snapshot.weeklyGoal)").font(.headline)
                    Gauge(value: entry.weeklyProgress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                    Text("widget.weekly.streak \(snapshot.streakWeeks)").font(.caption2)
                }
            } else {
                Text("widget.state.signedout").font(.caption)
            }
        default:
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Caption(key: "widget.weekly.name")
                    ZStack {
                        Ring(progress: entry.weeklyProgress)
                        VStack(spacing: 0) {
                            Text(verbatim: "\(entry.weeklyDone)/\(snapshot.weeklyGoal)")
                                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text("widget.weekly.workouts").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Label {
                        Text("widget.weekly.streak \(snapshot.streakWeeks)").monospacedDigit()
                    } icon: {
                        Image(systemName: "flame.fill")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(LiveStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .foregroundStyle(.white)
            } else {
                Placeholder(state: .signedOut).foregroundStyle(.white)
            }
        }
    }
}

// MARK: Previews

#Preview("Score", as: .systemSmall) {
    ScoreWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.noScore
    SnapshotEntry.signedOut
}

#Preview("Today", as: .systemMedium) {
    TodayWorkoutWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.signedOut
}

#Preview("Weekly", as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    SnapshotEntry.sample
    SnapshotEntry.signedOut
}
