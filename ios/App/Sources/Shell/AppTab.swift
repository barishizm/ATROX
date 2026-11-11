import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today, workout, analysis, coach, profile

    var title: LocalizedStringKey {
        switch self {
        case .today: "tab.today"
        case .workout: "tab.workout"
        case .analysis: "tab.analysis"
        case .coach: "tab.coach"
        case .profile: "tab.profile"
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
