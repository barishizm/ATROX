import XCTest

/// Buttons are found by their English label: the app's root view sets a blanket `root` identifier that
/// overrides button identifiers (text fields keep theirs).
/// Onboarding part 1 against the in-memory auth/data stack (`-uitest-fake-auth`), in English.
final class OnboardingUITests: XCTestCase {
    @MainActor
    private func launchIntoOnboarding() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-fake-auth", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testQuestionsAdvanceOneAtATimeAndBackReturns() throws {
        let app = launchIntoOnboarding()
        let apple = app.buttons["welcome-apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        apple.tap()

        let first = app.textFields["onboarding-first-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(next.isEnabled, "A first name is required")
        XCTAssertFalse(app.buttons["Back"].isEnabled, "No back on the first question")

        first.tap()
        first.typeText("Ada")
        XCTAssertTrue(next.isEnabled)
        next.tap()

        XCTAssertTrue(app.datePickers["onboarding-birth-date"].waitForExistence(timeout: 5)
            || app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "Keyboard must close after the name step")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.textFields["onboarding-first-name"].waitForExistence(timeout: 5))
    }
}
