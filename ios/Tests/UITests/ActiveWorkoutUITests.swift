import XCTest

/// Start an empty workout, add an exercise, complete three pre-filled sets with one tap each, finish.
/// The first completed set starts the rest timer, which shows the notification explanation once (P037).
final class ActiveWorkoutUITests: XCTestCase {
    @MainActor
    func testStartCompleteThreeSetsAndFinish() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-fake-auth", "-uitest-onboarded", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let workoutTab = app.tabBars.buttons["Workout"]
        XCTAssertTrue(workoutTab.waitForExistence(timeout: 15), app.debugDescription)
        workoutTab.tap()
        app.buttons["Start empty workout"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["active-workout-root"].waitForExistence(timeout: 10)
            || app.buttons["workout-add-exercise"].waitForExistence(timeout: 10), app.debugDescription)

        app.buttons["Add exercise"].firstMatch.tap()
        // Library rows only: `app.cells` would also match the workout list behind the sheet.
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'library-row-'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), app.debugDescription)
        firstRow.tap()
        let addButton = app.buttons["library-add-button"]
        if addButton.waitForExistence(timeout: 3) { addButton.tap() }

        for index in 0..<3 {
            let complete = app.buttons["set-complete-\(index)"]
            XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
            complete.tap()
            if index == 0 {
                // The first rest timer ever explains notifications first (a reused simulator may have seen it).
                let later = app.buttons["rest-primer-later"]
                if later.waitForExistence(timeout: 5) { later.tap() }
                XCTAssertTrue(app.buttons["rest-skip"].waitForExistence(timeout: 5), app.debugDescription)
            }
        }
        XCTAssertTrue(app.buttons["Undo complete"].firstMatch.exists)

        app.buttons["workout-finish"].tap()
        // The confirmation dialog's button is on top; the toolbar button of the same name stays behind it.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Finish'"))
        XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        confirm.allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(app.buttons["start-empty-workout"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
