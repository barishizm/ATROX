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
    private func launchIntoOnboarding(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += extra
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

        // Consents (P020): terms first, then the opt-in contribution screen — no pre-ticked box.
        let accept = app.buttons["I agree and continue"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.switches.firstMatch.exists, "No consent checkbox")
        accept.tap()

        let contribute = app.buttons["Contribute anonymously"]
        XCTAssertTrue(contribute.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Not now"].exists)
        let details = app.buttons["What is shared?"]
        XCTAssertTrue(details.exists)
        details.tap()
        XCTAssertTrue(app.staticTexts["Never shared"].waitForExistence(timeout: 5), app.debugDescription)
        contribute.tap()

        // First strength profile (P021): one set is enough for a score.
        XCTAssertTrue(app.staticTexts["Your best sets"].waitForExistence(timeout: 10), app.debugDescription)
        let weight = app.textFields.firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5), app.debugDescription)
        weight.tap()
        weight.typeText("80")
        let seeScore = app.buttons["See my score"]
        XCTAssertTrue(seeScore.waitForExistence(timeout: 5), app.debugDescription)
        seeScore.tap()

        XCTAssertTrue(app.staticTexts["Your first scores"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["This is a first estimate; it gets sharper as you log workouts."].exists)
        XCTAssertTrue(app.buttons["Let's go"].exists)
    }

    /// P023: the Health shortcut proposes sample values; nothing changes until the user says yes.
    @MainActor
    func testAppleHealthShortcutProposesValuesAndAppliesThemOnYes() throws {
        let app = launchIntoOnboarding(extra: ["-uitest-fake-health"])
        app.buttons["welcome-apple"].tap()
        let first = app.textFields["onboarding-first-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        first.tap()
        first.typeText("Ada")
        let next = app.buttons["Continue"]
        for _ in 0..<4 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        let health = app.buttons["Fill in from Apple Health"]
        XCTAssertTrue(health.waitForExistence(timeout: 10), app.debugDescription)
        health.tap()
        let alert = app.alerts["Use these from Apple Health?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["Not now"].tap()
        health.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Use"].tap()
        XCTAssertTrue(app.pickerWheels["182 cm"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testAppleHealthShortcutIsHiddenWhenHealthIsMissing() throws {
        let app = launchIntoOnboarding()
        app.buttons["welcome-apple"].tap()
        let first = app.textFields["onboarding-first-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        first.tap()
        first.typeText("Ada")
        let next = app.buttons["Continue"]
        for _ in 0..<4 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Fill in from Apple Health"].exists)
    }
}
