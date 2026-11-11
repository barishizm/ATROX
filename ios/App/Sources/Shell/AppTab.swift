import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today, workout, analysis, coach, profile

    var title: LocalizedStringKey {
        switch self {
        case .today: "shell.tabbar.today"
        case .workout: "shell.tabbar.workout"
        case .analysis: "shell.tabbar.analysis"
        case .coach: "shell.tabbar.coach"
        case .profile: "shell.tabbar.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .workout: "dumbbell"
        case .analysis: "chart.line.uptrend.xyaxis"
        case .coach: "bubble.left.and.text.bubble.right"
        case .profile: "person"
        }
    }
}
