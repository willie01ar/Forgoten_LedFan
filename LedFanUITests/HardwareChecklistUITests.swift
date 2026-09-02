import XCTest

/// The manual hardware checklist from docs/testing.md, runnable on demand. Skipped unless
/// LEDFAN_HARDWARE is set, so the suite never depends on the fan.
///
///   TEST_RUNNER_LEDFAN_HARDWARE=attached xcodebuild ... -only-testing:LedFanUITests/HardwareChecklistUITests test
///   TEST_RUNNER_LEDFAN_HARDWARE=absent   ... with the data cable unplugged
final class HardwareChecklistUITests: XCTestCase {
    private var hardwareState: String? { ProcessInfo.processInfo.environment["LEDFAN_HARDWARE"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(hardwareState == nil, "Set LEDFAN_HARDWARE=attached or =absent to run the hardware checklist.")
    }

    @MainActor
    func testConnectsSendsAndDisconnectsWithTheFanAttached() throws {
        try XCTSkipUnless(hardwareState == "attached")
        let app = XCUIApplication()
        app.launch()
        selectUSBFan(in: app)

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Connected"].waitForExistence(timeout: 10),
                      "Status was: \(statusText(in: app))")

        let sendButton = app.buttons["Send the message to the fan"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.click()
        recordSendOutcome(in: app)

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testReportsTheCableTrapWithTheFanAbsent() throws {
        try XCTSkipUnless(hardwareState == "absent")
        let app = XCUIApplication()
        app.launch()
        selectUSBFan(in: app)

        app.buttons["Connect to the fan"].click()
        // The combined status element exposes its text as value on macOS, so match either field.
        let failure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'data cable' OR value CONTAINS 'data cable'")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10), "Status was: \(statusText(in: app))")
        XCTAssertFalse(app.buttons["Send the message to the fan"].isEnabled)
    }

    // MARK: - Helpers

    @MainActor
    private func selectUSBFan(in app: XCUIApplication) {
        XCTAssertTrue(app.textFields["Message to display on the fan"].waitForExistence(timeout: 5))
        app.radioButtons["USB fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func statusText(in app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex
            .map { $0.label.isEmpty ? String(describing: $0.value ?? "") : $0.label }
            .joined(separator: " | ")
    }

    /// F5 is blocked on the protocol, so the send outcome is recorded rather than asserted.
    @MainActor
    private func recordSendOutcome(in app: XCUIApplication) {
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch
        let outcome = error.waitForExistence(timeout: 3) ? error.label : "Send completed without a reported error."
        let attachment = XCTAttachment(string: outcome)
        attachment.name = "Send outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Hardware connected"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
