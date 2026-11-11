import XCTest

/// Buttons are found by their English label: the app's root view sets a blanket `root` identifier that
/// overrides button identifiers (text fields keep theirs).
/// Onboarding parts 1–2 against the in-memory auth/data stack (`-uitest-fake-auth`), in English.
final class OnboardingUITests: XCTestCase {
    /// A selection card: its label is "<title>, <description>", so match on the title prefix.
    @MainActor
    private func card(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

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

    /// Part 2 end to end: ten questions, selection cards, and the interim "saved" screen.
    @MainActor
    func testTrainingProfileQuestionsCompleteTheFlow() throws {
        let app = launchIntoOnboarding()
        app.buttons["welcome-apple"].tap()
        let first = app.textFields["onboarding-first-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        first.tap()
        first.typeText("Ada")
        let next = app.buttons["Continue"]
        // name, birth date, sex, units, body
        for _ in 0..<5 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }

        // Experience: nothing is pre-selected, Continue stays off until a card is chosen.
        let experience = card(app, "6 months")
        XCTAssertTrue(experience.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(next.isEnabled)
        experience.tap()
        XCTAssertTrue(next.isEnabled)
        next.tap()

        let goal = card(app, "Strength")
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap()
        next.tap()

        XCTAssertTrue(card(app, "5 days").waitForExistence(timeout: 5))
        card(app, "5 days").tap()
        next.tap()

        let equipment = card(app, "Full gym")
        XCTAssertTrue(equipment.waitForExistence(timeout: 5))
        equipment.tap()
        next.tap()

        let none = card(app, "No limitations")
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Pick an area or 'No limitations'")
        none.tap()
        XCTAssertTrue(next.isEnabled)
        next.tap()

        XCTAssertTrue(app.staticTexts["Training profile saved"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
