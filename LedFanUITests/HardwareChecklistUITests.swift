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

    /// D22 check: four fields filled with gaps between them; the fan must cycle exactly four.
    @MainActor
    func testConnectsSendsAndDisconnectsWithTheFanAttached() throws {
        try XCTSkipUnless(hardwareState == "attached")
        let app = XCUIApplication()
        let seed = LedFanUITests.encodedSeed(["Hello World. I hold 8 Msg.", "", "*Mom Pick me up @4P*", "", "HELLO WILLIE", "", "", "Message eight"])
        app.launchArguments = LedFanUITests.mainDisplayWindow + ["-transientStore", "YES", "-seedDrafts", seed]
        app.launch()
        XCTAssertTrue(app.textFields["Message 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].exists, "USB fan is the default")

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Connected"].waitForExistence(timeout: 10),
                      "Status was: \(statusText(in: app))")

        let sendButton = app.buttons["Send the filled messages to the fan"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.click()
        let success = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Sent 4 messages to SONiX LED fan'")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 200), "Status was: \(statusText(in: app))")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists)
        let note = XCTAttachment(string: (success.value as? String) ?? "no success line")
        note.name = "Success line"
        note.lifetime = .keepAlways
        add(note)
        attachScreenshot(of: app, named: "Hardware connected, four messages sent")

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testReportsTheCableTrapWithTheFanAbsent() throws {
        try XCTSkipUnless(hardwareState == "absent")
        let app = XCUIApplication()
        app.launchArguments = ["-transientStore", "YES"] + LedFanUITests.mainDisplayWindow
        app.launch()
        XCTAssertTrue(app.textFields["Message 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists, "calm before Connect")

        app.buttons["Connect to the fan"].click()
        let failure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'data cable' OR value CONTAINS 'data cable'")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10), "Status was: \(statusText(in: app))")
        XCTAssertFalse(app.buttons["Send the filled messages to the fan"].isEnabled)
    }

    // MARK: - Helpers

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
