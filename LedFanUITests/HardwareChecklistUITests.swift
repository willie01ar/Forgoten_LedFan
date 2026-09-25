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

        // All eight slots, the factory demo's first four (lowercase included) plus four of ours.
        let messageField = app.textFields["Message to display on the fan"]
        let texts = ["Hello World. I hold 8 Msg.", "26 letters in each Msg", "I'm your *NOTE PAD*", "*Mom Pick me up @4P*",
                     "HELLO WILLIE", "Slot six", "Slot seven", "Slot eight"]
        for (index, text) in texts.enumerated() {
            app.radioButtons["\(index + 1)"].click()
            messageField.click()
            messageField.typeKey("a", modifierFlags: .command)
            messageField.typeText(text)
            XCTAssertTrue(app.otherElements["Fan preview showing \(text) in slot \(index + 1)"].waitForExistence(timeout: 2))
        }
        app.radioButtons["1"].click()

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Connected"].waitForExistence(timeout: 10),
                      "Status was: \(statusText(in: app))")

        // D17/D19: the app writes all eight slots in the PearlFan protocol and reports what
        // came back. A silent head costs one second per report, so allow up to 320 s.
        let sendButton = app.buttons["Send all eight slots to the fan"]
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'PearlFan protocol'")).firstMatch.exists)
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.click()
        let receipt = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Published all 8 slots'")).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 400))
        let note = XCTAttachment(string: (receipt.value as? String) ?? "no receipt")
        note.name = "Receipt"
        note.lifetime = .keepAlways
        add(note)
        attachScreenshot(of: app, named: "Hardware connected, PearlFan message written")

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
        XCTAssertFalse(app.buttons["Send all eight slots to the fan"].isEnabled)
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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
