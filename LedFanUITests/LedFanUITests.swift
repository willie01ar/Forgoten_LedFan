import XCTest

/// Milestone 1 end to end: type, preview, connect to the simulated fan, send. No hardware.
/// XCTest rather than Swift Testing because XCUIApplication requires it. Every launch uses
/// the transient store, so the tests never read or write the real container.
final class LedFanUITests: XCTestCase {
    private let twentySixCharacters = "THE QUICK BROWN FOX JUMPS!"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(light: Bool = false, columnsPerRevolution: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-transientStore", "YES"]
        if light { app.launchArguments += ["-NSRequiresAquaSystemAppearance", "YES"] }
        if let columnsPerRevolution { app.launchArguments += ["-columnsPerRevolution", String(columnsPerRevolution)] }
        app.launch()
        return app
    }

    @MainActor
    func testTypingConnectingAndSendingOnTheSimulatedFan() throws {
        let app = launch()

        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].exists)
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO in slot 1"].waitForExistence(timeout: 3))

        let sendButton = app.buttons["Send the message to the fan"]
        XCTAssertFalse(sendButton.isEnabled, "Send must be disabled until connected")

        replaceText(in: messageField, with: twentySixCharacters)
        XCTAssertTrue(app.otherElements["Fan preview showing \(twentySixCharacters) in slot 1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["26 of 26 characters"].exists)

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(sendButton.isEnabled)

        sendButton.click()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Stored in slot 1 on the simulated fan'")).firstMatch.waitForExistence(timeout: 2))
        attachScreenshot(of: app, named: "Legible preview, dark")

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testOverLengthInputIsRefusedVisibly() throws {
        let app = launch()

        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))

        replaceText(in: messageField, with: twentySixCharacters + "?")
        XCTAssertTrue(app.staticTexts["27 of 26 characters"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS '1 character over'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Send the message to the fan"].isEnabled)
        XCTAssertEqual(messageField.value as? String, twentySixCharacters + "?", "the draft must not be cut")
    }

    @MainActor
    func testSlotsKeepTheirOwnText() throws {
        let app = launch()

        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO in slot 1"].waitForExistence(timeout: 3))

        app.radioButtons["2"].click()
        XCTAssertTrue(app.otherElements["Fan preview, slot 2, empty"].waitForExistence(timeout: 2))
        replaceText(in: messageField, with: "SECOND")
        XCTAssertTrue(app.otherElements["Fan preview showing SECOND in slot 2"].waitForExistence(timeout: 2))

        app.radioButtons["1"].click()
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO in slot 1"].waitForExistence(timeout: 2))
        app.radioButtons["2"].click()
        XCTAssertTrue(app.otherElements["Fan preview showing SECOND in slot 2"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLightAppearanceRendersTheSameControls() throws {
        let app = launch(light: true)

        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        replaceText(in: messageField, with: twentySixCharacters)
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Legible preview, light")
    }

    // MARK: - Scrolling evidence (Milestone 3)

    /// At the default 180 columns no message is longer than a revolution, so the frames
    /// are captured at a narrower preview width where the 26-character message scrolls.
    @MainActor
    func testALongMessageScrollsDark() throws {
        try captureScrollFrames(light: false)
    }

    @MainActor
    func testALongMessageScrollsLight() throws {
        try captureScrollFrames(light: true)
    }

    @MainActor
    func testAShortMessageStandsStill() throws {
        let app = launch(columnsPerRevolution: 120)
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO in slot 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["Fan preview showing HELLO in slot 1, scrolling"].exists)
    }

    /// Screenshots for the architect's `columnsPerRevolution` decision (Task 3).
    @MainActor
    func testCandidateWidthsForTheArchitect() throws {
        for columns in [120, 150, 180] {
            let app = launch(columnsPerRevolution: columns)
            let messageField = app.textFields["Message to display on the fan"]
            XCTAssertTrue(messageField.waitForExistence(timeout: 5))
            replaceText(in: messageField, with: twentySixCharacters)
            let preview = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Fan preview showing \(twentySixCharacters) in slot 1")).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 2))
            attachScreenshot(of: app, named: "Candidate \(columns) columns")
            app.terminate()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func captureScrollFrames(light: Bool) throws {
        let app = launch(light: light, columnsPerRevolution: 120)
        let messageField = app.textFields["Message to display on the fan"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        replaceText(in: messageField, with: twentySixCharacters)
        XCTAssertTrue(app.otherElements["Fan preview showing \(twentySixCharacters) in slot 1, scrolling"].waitForExistence(timeout: 2))

        for index in 1...6 {
            attachScreenshot(of: app, named: "Scroll \(light ? "light" : "dark") frame \(index)")
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
