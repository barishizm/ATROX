import XCTest

/// Runs the signed-out flow against the in-memory auth service (`-uitest-fake-auth`), in English.
/// The app is launched from each (main-actor) test: `XCUIApplication` is main-actor isolated, while
/// `setUp` overrides are nonisolated on older SDKs.
final class AuthFlowUITests: XCTestCase {
    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-fake-auth", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testWelcomeShowsAppleFirstThenGoogleThenEmail() throws {
        let app = launchApp()
        let apple = app.buttons["welcome-apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        let google = app.buttons["welcome-google"]
        let email = app.buttons["welcome-email"]
        XCTAssertTrue(google.exists && email.exists)
        XCTAssertLessThan(apple.frame.minY, google.frame.minY)
        XCTAssertLessThan(google.frame.minY, email.frame.minY)
    }

    @MainActor
    func testEmailSignUpLeadsToVerificationScreen() throws {
        let app = launchApp()
        let email = app.buttons["welcome-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()

        let submit = app.buttons["auth-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "Submit stays disabled until the form is valid")

        type("tester@example.com", into: app.textFields["auth-email-field"], in: app)
        type("Abcdef12", into: app.secureTextFields["auth-password-field"], in: app)
        XCTAssertTrue(waitUntilEnabled(submit), "Submit should enable once the form is valid:\n\(app.debugDescription)")
        submit.tap()

        let message = app.staticTexts["verify-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Verification screen did not appear:\n\(app.debugDescription)")
        XCTAssertTrue(message.label.contains("tester@example.com"), "Unexpected message: \(message.label)")
        XCTAssertTrue(app.buttons["verify-resend"].exists)
    }

    @MainActor
    func testWrongPasswordShowsErrorMessage() throws {
        let app = launchApp()
        let signIn = app.buttons["welcome-signin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()

        type("nobody@example.com", into: app.textFields["auth-email-field"], in: app)
        type("WrongPass1", into: app.secureTextFields["auth-password-field"], in: app)
        app.buttons["auth-submit"].tap()

        let error = app.staticTexts.matching(identifier: "auth-error").firstMatch
        let banner = error.exists ? error : app.otherElements["auth-error"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.localizedCaseInsensitiveContains("incorrect")
            || banner.label.localizedCaseInsensitiveContains("wrong")
            || banner.label.localizedCaseInsensitiveContains("invalid"), "Unexpected error text: \(banner.label)")
        XCTAssertFalse(banner.label.contains("auth.error"), "Message must be localized, not a key")
    }

    @MainActor
    func testForgotPasswordShowsConfirmation() throws {
        let app = launchApp()
        let signIn = app.buttons["welcome-signin"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()
        type("tester@example.com", into: app.textFields["auth-email-field"], in: app)
        app.buttons["auth-forgot"].tap()

        let submit = app.buttons["auth-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["auth-email-field"].value as? String, "tester@example.com")
        submit.tap()
        XCTAssertTrue(app.staticTexts["reset-sent-message"].waitForExistence(timeout: 10))
    }

    // MARK: Helpers

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// iOS offers a generated password on new-password fields (a popover with a close button). Close it so
    /// it doesn't swallow keystrokes; harmless when no suggestion is shown.
    @MainActor
    private func dismissStrongPasswordSuggestion(in app: XCUIApplication) {
        let close = app.buttons.matching(NSPredicate(format: "identifier == 'xmark'")).firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() }
        let decline = app.buttons["Choose My Own Password"]
        if decline.exists { decline.tap() }
    }

    /// Types into a field and verifies every character landed; a short count clears and retypes.
    @MainActor
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for attempt in 0..<3 {
            if attempt == 0 {
                field.tap()
                // Only password fields get the suggestion; waiting for it on other fields costs ~4 s each.
                if field.elementType == .secureTextField {
                    dismissStrongPasswordSuggestion(in: app)
                }
            }
            field.typeText(text)
            let typed = (field.value as? String) ?? ""
            if typed.count == text.count { return }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2))
        }
        XCTFail("Could not type into \(field.identifier)")
    }
}
