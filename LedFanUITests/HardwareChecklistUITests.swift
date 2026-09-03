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
        app.launchArguments = ["-transientStore", "YES"]
        app.launch()
        selectUSBFan(in: app)

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Connected"].waitForExistence(timeout: 10),
                      "Status was: \(statusText(in: app))")

        // D9: the app never writes to the head. Send stays off and the UI says why.
        let sendButton = app.buttons["Send the message to the fan"]
        XCTAssertFalse(sendButton.isEnabled, "Send must be disabled on hardware until the table format is known")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS \"isn't known yet\"")).firstMatch.exists)
        attachScreenshot(of: app, named: "Hardware connected, send refused")

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testReportsTheCableTrapWithTheFanAbsent() throws {
        try XCTSkipUnless(hardwareState == "absent")
        let app = XCUIApplication()
        app.launchArguments = ["-transientStore", "YES"]
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
        XCTAssertFalse(app.buttons["Send the message to the fan"].isEnabled)
    }

    @MainActor
    private func statusText(in app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex
            .map { $0.label.isEmpty ? String(describing: $0.value ?? "") : $0.label }
            .joined(separator: " | ")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
