import XCTest

/// Milestone 1 end to end: type, preview, connect to the simulated fan, send. No hardware.
/// XCTest rather than Swift Testing because XCUIApplication requires it.
final class LedFanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTypingConnectingAndSendingOnTheSimulatedFan() throws {
        let app = XCUIApplication()
        app.launch()

        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].exists)
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO"].exists)

        let sendButton = app.buttons["Send the message to the fan"]
        XCTAssertFalse(sendButton.isEnabled, "Send must be disabled until connected")

        messageField.click()
        messageField.typeKey("a", modifierFlags: .command)
        messageField.typeText("FAN OK")
        XCTAssertTrue(app.otherElements["Fan preview showing FAN OK"].waitForExistence(timeout: 2))

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(sendButton.isEnabled)

        sendButton.click()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists)
        attachScreenshot(of: app, named: "Milestone 1")

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testLightAppearanceRendersTheSameControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-NSRequiresAquaSystemAppearance", "YES"]
        app.launch()

        XCTAssertTrue(app.textFields["Message to display on the fan"].waitForExistence(timeout: 5))
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Light appearance")
    }

    // MARK: - Helpers

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
