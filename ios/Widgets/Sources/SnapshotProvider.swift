import SwiftUI
import WidgetKit

/// One entry of any of the three widgets: the snapshot the app last wrote (nil = signed out) at a point in time.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var state: WidgetContentState { WidgetContentState(snapshot) }
    var weeklyDone: Int { snapshot?.weeklyDone(at: date) ?? 0 }
    var weeklyProgress: Double { snapshot?.weeklyProgress(at: date) ?? 0 }

    /// Sample data for the widget gallery and previews.
    static let sample = SnapshotEntry(date: .now, snapshot: .sample)
    static let signedOut = SnapshotEntry(date: .now, snapshot: nil)
    static let noScore = SnapshotEntry(date: .now, snapshot: .sample.withoutScore)
}

/// Reads the app group snapshot; the app reloads the timelines when it changes, and the plan below is the fallback
/// for days the app is not opened.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .sample : SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.appGroup()?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.appGroup()?.read()
        let plan = WidgetTimelinePlan.plan(for: snapshot, now: .now)
        completion(Timeline(
            entries: plan.entryDates.map { SnapshotEntry(date: $0, snapshot: snapshot) },
            policy: .after(plan.reloadAfter)
        ))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        generatedAt: .now,
        score: Score(value: 72, isProvisional: false, change: 3),
        next: PlannedDay(
            routineId: UUID(), dayId: UUID(), routineName: "Upper / Lower", dayName: "Upper A", exerciseCount: 6
        ),
        weeklyDone: 2, weeklyGoal: 4, streakWeeks: 5, trainedToday: false,
        weekEndsAt: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.end ?? .now.addingTimeInterval(86_400)
    )

    var withoutScore: WidgetSnapshot {
        var copy = self
        copy.score = nil
        return copy
    }
}
