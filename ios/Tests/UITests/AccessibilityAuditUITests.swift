import XCTest

/// Automated accessibility audits on the critical screens (P097) plus the core workout flow at the largest
/// accessibility text size. Audits skip `.dynamicType`/`.textClipped`: SwiftUI charts and system bars report
/// false positives there (documented in docs/ERISILEBILIRLIK.md); the large-text flow test covers clipping instead.
final class AccessibilityAuditUITests: XCTestCase {
    private static let auditTypes: XCUIAccessibilityAuditType = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait,
    ]

    @MainActor
    private func launch(largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-fake-auth", "-uitest-onboarded", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    @MainActor
    private func select(_ tab: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }

    @MainActor
    func testCriticalTabsPassAudit() throws {
        let app = launch()
        for tab in ["Today", "Workout", "Analysis", "Coach", "Profile"] {
            select(tab, in: app)
            try app.performAccessibilityAudit(for: Self.auditTypes)
        }
    }

    @MainActor
    func testActiveWorkoutPassesAudit() throws {
        let app = launch()
        startWorkoutWithExercise(app)
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    /// Start → complete a set → finish, at the largest accessibility size (the set row switches to a vertical layout).
    @MainActor
    func testWorkoutFlowAtLargestTextSize() throws {
        let app = launch(largeText: true)
        startWorkoutWithExercise(app)
        let complete = app.buttons["set-complete-0"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        complete.tap()
        let later = app.buttons["rest-primer-later"]
        if later.waitForExistence(timeout: 5) { later.tap() }
        XCTAssertTrue(app.buttons["Undo complete"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["workout-finish"].exists)
    }

    @MainActor
    private func startWorkoutWithExercise(_ app: XCUIApplication) {
        select("Workout", in: app)
        app.buttons["Start empty workout"].firstMatch.tap()
        XCTAssertTrue(app.buttons["workout-add-exercise"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Add exercise"].firstMatch.tap()
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'library-row-'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), app.debugDescription)
        firstRow.tap()
        let addButton = app.buttons["library-add-button"]
        if addButton.waitForExistence(timeout: 3) { addButton.tap() }
        XCTAssertTrue(app.buttons["set-complete-0"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
