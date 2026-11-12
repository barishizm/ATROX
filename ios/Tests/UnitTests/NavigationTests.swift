import Foundation
import Testing

@testable import ATROX

@MainActor
struct NavigationTests {
    @Test func routerPushPopAndReset() {
        let router = TabRouter<WorkoutRoute>()
        router.push(.exerciseLibrary)
        router.push(.activeWorkout(id: UUID()))
        #expect(router.path.count == 2)
        router.pop()
        #expect(router.path == [.exerciseLibrary])
        router.popToRoot()
        #expect(router.path.isEmpty)
        router.pop()  // popping an empty stack is a no-op
        #expect(router.path.isEmpty)
    }

    @Test func fiveTabsInOrder() {
        #expect(AppTab.allCases == [.today, .workout, .analysis, .coach, .profile])
    }

    @Test func everyLogCategoryHasALogger() {
        for category in LogCategory.allCases {
            #expect(Log.logger(for: category).category == category)
        }
        #expect(LogCategory.allCases.map(\.rawValue) == ["app", "data", "sync", "score", "coach", "purchase"])
    }
}
