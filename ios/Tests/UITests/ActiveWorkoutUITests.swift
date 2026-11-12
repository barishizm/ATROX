import XCTest

/// Start an empty workout, add an exercise, complete three pre-filled sets with one tap each, finish.
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
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), app.debugDescription)
        firstRow.tap()
        let addButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add'")).firstMatch
        if addButton.waitForExistence(timeout: 3) { addButton.tap() }

        for index in 0..<3 {
            let complete = app.buttons["set-complete-\(index)"]
            XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
            complete.tap()
        }
        XCTAssertTrue(app.buttons["Undo complete"].firstMatch.exists)

        app.buttons["workout-finish"].tap()
        app.buttons["Finish"].firstMatch.tap()
        XCTAssertTrue(app.buttons["start-empty-workout"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
