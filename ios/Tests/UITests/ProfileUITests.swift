import XCTest

/// Profile tab against the seeded in-memory stack (`-uitest-fake-auth -uitest-onboarded`), in English.
/// Buttons are found by label: the app's root view sets a blanket `root` identifier that overrides them.
final class ProfileUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-fake-auth", "-uitest-onboarded", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 15), app.debugDescription)
        profileTab.tap()
        return app
    }

    @MainActor
    private func open(_ app: XCUIApplication, _ label: String) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
    }

    @MainActor
    func testProfileSummaryShowsSeededData() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Ada Lovelace"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["ada@example.com"].exists)
        XCTAssertTrue(app.staticTexts["61"].exists, "Latest weight")
    }

    @MainActor
    func testEditingTheProfileSavesAndShowsOnTheSummary() throws {
        let app = launch()
        open(app, "Edit profile")
        let first = app.textFields["profile-edit-first-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        let save = app.buttons["Save"]
        XCTAssertFalse(save.isEnabled, "No changes yet")
        first.tap()
        first.press(forDuration: 1.0)
        app.menuItems["Select All"].firstMatch.tap()
        first.typeText("Augusta")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Augusta Lovelace"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testWeightChartAndAddingAMeasurement() throws {
        let app = launch()
        open(app, "Body measurements")
        XCTAssertTrue(app.otherElements["weight-chart"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Add measurement"].tap()
        let field = app.textFields["measurement-weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        app.menuItems["Select All"].firstMatch.tap()
        field.typeText("60")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["60 kg"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testDeletingTheAccountNeedsTheWordAndSignsOut() throws {
        let app = launch()
        open(app, "Settings")
        let delete = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Delete my account")).firstMatch
        if !delete.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()

        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        next.tap()
        let field = app.textFields["delete-confirm-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let final = app.buttons["Delete forever"]
        XCTAssertFalse(final.isEnabled, "Needs the confirmation word")
        field.tap()
        field.typeText("delete")
        XCTAssertTrue(final.isEnabled)
        final.tap()
        XCTAssertTrue(app.buttons["welcome-apple"].waitForExistence(timeout: 10), "Back at the welcome screen")
    }

    @MainActor
    func testAboutShowsVersionAndLicenses() throws {
        let app = launch()
        open(app, "About")
        XCTAssertTrue(app.staticTexts["Version"].waitForExistence(timeout: 10), app.debugDescription)
        open(app, "Open-source licenses")
        XCTAssertTrue(app.staticTexts["supabase-swift"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
