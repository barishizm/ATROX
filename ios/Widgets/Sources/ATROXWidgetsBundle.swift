import SwiftUI
import WidgetKit

@main
struct ATROXWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        ScoreWidget()
        TodayWorkoutWidget()
        WeeklyGoalWidget()
        StartWorkoutControl()
    }
}
