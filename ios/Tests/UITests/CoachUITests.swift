import XCTest

/// Coach tab against the scripted coach (`-uitest-fake-coach`, no network), in English:
/// send a message → streamed answer → proposal card → Apply → the program exists in the Workout tab.
final class CoachUITests: XCTestCase {
    @MainActor
    private func launch(acceptConsent: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-fake-auth", "-uitest-onboarded", "-uitest-fake-coach", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let tab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), app.debugDescription)
        tab.tap()
        if acceptConsent {
            let accept = app.buttons["coach-consent-accept"]
            XCTAssertTrue(accept.waitForExistence(timeout: 10), app.debugDescription)
            accept.tap()
        }
        return app
    }

    @MainActor
    func testNothingIsShownBeforeConsentAndDecliningExplains() throws {
        let app = launch(acceptConsent: false)
        XCTAssertTrue(app.buttons["coach-consent-decline"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.textFields["coach-input"].exists)
        app.buttons["coach-consent-decline"].tap()
        XCTAssertTrue(app.staticTexts["The coach is off"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.textFields["coach-input"].exists)
    }

    @MainActor
    func testEmptyConversationOffersFourStarterQuestions() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["coach-suggestion"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "coach-suggestion").count, 4)
    }

    @MainActor
    func testAskingForAProgramShowsACardAndApplyingCreatesTheProgram() throws {
        let app = launch()
        let input = app.textFields["coach-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
        input.tap()
        input.typeText("Make me a 3-day program")
        app.buttons["coach-send"].tap()

        XCTAssertTrue(app.staticTexts["Coach 3-Day Plan"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["coach-quota"].waitForExistence(timeout: 5) || app.otherElements["coach-quota"].exists)
        let apply = app.buttons["proposal-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15), app.debugDescription)
        apply.tap()

        let open = app.buttons["coach-open-program"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Applied"].firstMatch.exists)
        open.tap()

        // The Workout tab shows the new program with its three days.
        XCTAssertTrue(app.staticTexts["Day A"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Day C"].exists)
    }

    @MainActor
    func testRejectingACardKeepsTheProgramOut() throws {
        let app = launch()
        let input = app.textFields["coach-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
        input.tap()
        input.typeText("Make me a program")
        app.buttons["coach-send"].tap()
        let reject = app.buttons["proposal-reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 15), app.debugDescription)
        reject.tap()
        XCTAssertTrue(app.staticTexts["Rejected"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["proposal-apply"].exists)
    }
}
