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

    func testCompanionInfoKeepsUnpublishedDownloadsDisabled() {
        app.buttons["info-companions"].click()
        XCTAssertTrue(app.staticTexts["Info & Companions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not published yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["download-mac"].isEnabled)
        XCTAssertFalse(app.buttons["download-flipper"].isEnabled)
        app.buttons["Close Info & Companions"].click()
        XCTAssertTrue(app.staticTexts["Quick Paste"].firstMatch.exists)
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

    func testSendStartsInSaveModeWithoutUSBExecution() {
        app.staticTexts["Timestamp"].firstMatch.click()
        app.buttons["save-macro-flipper"].click()
        XCTAssertTrue(app.textFields["Name on Flipper"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["Store this plaintext snapshot on the Flipper SD card"].exists)
        XCTAssertFalse(app.checkBoxes["The intended USB target and input field are focused"].exists)
        XCTAssertFalse(app.buttons["run-confirmed"].isEnabled)
        app.buttons["Cancel"].firstMatch.click()
        app.buttons["review-macro"].click()
        XCTAssertTrue(app.checkBoxes["The intended USB target and input field are focused"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run-confirmed"].isEnabled)
    }

    func testMousePresetHasHoursControlsAndOfflineStopSafety() {
        app.buttons["new-mouse-jiggle"].click()
        XCTAssertTrue(app.textFields["macro-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Duration (minutes)"].exists)
        XCTAssertTrue(app.textFields["Minimum interval (seconds)"].exists)
        XCTAssertTrue(app.textFields["Maximum interval (seconds)"].exists)
        app.buttons["save-macro"].click()
        app.buttons["review-macro"].click()
        let standalone = app.checkBoxes["Continue on Flipper if this Mac disconnects"]
        XCTAssertTrue(standalone.waitForExistence(timeout: 5))
        XCTAssertEqual(standalone.value as? Int, 1)
        XCTAssertFalse(app.buttons["run-confirmed"].isEnabled)
    }
}
