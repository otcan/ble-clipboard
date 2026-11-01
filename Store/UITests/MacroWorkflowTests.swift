import XCTest

final class MacroWorkflowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }
    override func tearDown() { app.terminate() }

    func testStartersAndOfflineReviewCannotRun() {
        XCTAssertTrue(app.staticTexts["Quick Paste"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Timestamp"].firstMatch.click()
        app.buttons["review-macro"].click()
        XCTAssertTrue(app.buttons["run-confirmed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run-confirmed"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Timestamp review - disconnected"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Cancel"].firstMatch.click()
    }

    func testCreateAndEditMacroWithoutConnecting() {
        app.buttons["new-macro"].click()
        let name = app.textFields["macro-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Store Macro")
        XCTAssertEqual(name.value as? String, "Store Macro")
        let editor = app.sheets.textViews.firstMatch
        editor.click()
        editor.typeText("Hello [ENTER]")
        app.buttons["save-macro"].click()
        XCTAssertTrue(app.staticTexts["Store Macro"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["edit-macro"].click()
        XCTAssertEqual(app.textFields["macro-name"].value as? String, "Store Macro")
        app.buttons["Cancel"].firstMatch.click()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Saved macro workspace"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
