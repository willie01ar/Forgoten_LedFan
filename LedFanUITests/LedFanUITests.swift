import XCTest

/// End to end against the simulated fan. XCTest rather than Swift Testing because
/// XCUIApplication requires it. Every launch uses the transient store, so the tests never
/// read or write the real container. The USB fan is the launch default (D23), so each test
/// picks the simulated one first.
final class LedFanUITests: XCTestCase {
    private let twentySixCharacters = "THE QUICK BROWN FOX JUMPS!"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(light: Bool = false, columnsPerRevolution: Int? = nil, seed: [String]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-transientStore", "YES"] + Self.mainDisplayWindow
        if light { app.launchArguments += ["-NSRequiresAquaSystemAppearance", "YES"] }
        if let columnsPerRevolution { app.launchArguments += ["-columnsPerRevolution", String(columnsPerRevolution)] }
        if let seed { app.launchArguments += ["-seedDrafts", Self.encodedSeed(seed)] }
        app.launch()
        XCTAssertTrue(app.textFields["Message 1"].waitForExistence(timeout: 5))
        // A fresh window can still be settling when the first click lands; try once more.
        for _ in 0..<2 where !app.staticTexts["Simulated fan: Not connected"].exists {
            app.radioButtons["Simulated fan"].click()
            _ = app.staticTexts["Simulated fan: Not connected"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].exists)
        return app
    }

    /// Window screenshots only work on the primary display. Each test launch ignores saved
    /// window state and asks the app to place its window there.
    static let mainDisplayWindow = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
                                    "-pinWindowToPrimaryDisplay", "YES"]

    /// UserDefaults parses launch arguments as old-style plists and mangles asterisks and
    /// quotes, so the seed travels percent-encoded.
    static func encodedSeed(_ texts: [String]) -> String {
        texts.joined(separator: "|").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    @MainActor
    func testLaunchIsCalmWithTheUSBFanSelectedAndNoFanAttached() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-transientStore", "YES"] + Self.mainDisplayWindow
        app.launch()
        XCTAssertTrue(app.textFields["Message 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SONiX LED fan: Not connected"].exists, "USB fan is the default")
        XCTAssertEqual(app.radioButtons.firstMatch.label, "USB fan", "and the first segment")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Send the filled messages to the fan"].isEnabled)
    }

    @MainActor
    func testTypingConnectingAndSendingOnTheSimulatedFan() throws {
        let app = launch()
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO (message 1)"].waitForExistence(timeout: 3))

        let sendButton = app.buttons["Send the filled messages to the fan"]
        XCTAssertFalse(sendButton.isEnabled, "Send must be disabled until connected")

        replaceText(in: app.textFields["Message 1"], with: twentySixCharacters)
        XCTAssertTrue(app.otherElements["Fan preview showing \(twentySixCharacters) (message 1)"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Message 1: 26 of 26 characters"].exists)
        replaceText(in: app.textFields["Message 3"], with: "THIRD")

        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(sendButton.isEnabled)

        sendButton.click()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error:'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Sent 2 messages to Simulated fan'")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'report' OR value CONTAINS 'byte'")).firstMatch.exists, "no diagnostics in the interface")
        attachScreenshot(of: app, named: "Layout dark")

        app.buttons["Disconnect from the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Not connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled)
    }

    @MainActor
    func testOverLengthInputIsRefusedVisiblyInAnyField() throws {
        let app = launch()
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))

        let field = app.textFields["Message 5"]
        replaceText(in: field, with: twentySixCharacters + "?")
        XCTAssertTrue(app.staticTexts["Message 5: 27 of 26 characters"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Message 5 is 1 character over'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Send the filled messages to the fan"].isEnabled)
        XCTAssertEqual(field.value as? String, twentySixCharacters + "?", "the draft must not be cut")
    }

    @MainActor
    func testAllEmptyDisablesSend() throws {
        let app = launch(seed: ["", "", "", "", "", "", "", ""])
        // macOS gives Message 1 keyboard focus at launch, so the preview follows it: empty.
        XCTAssertTrue(app.otherElements["Fan preview, message 1, empty"].waitForExistence(timeout: 3))
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send the filled messages to the fan"].isEnabled)
    }

    @MainActor
    func testThePreviewFollowsFocusAndFieldsKeepTheirText() throws {
        let app = launch()
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO (message 1)"].waitForExistence(timeout: 3))

        let second = app.textFields["Message 2"]
        second.click()
        XCTAssertTrue(app.otherElements["Fan preview, message 2, empty"].waitForExistence(timeout: 2))
        second.typeText("SECOND")
        XCTAssertTrue(app.otherElements["Fan preview showing SECOND (message 2)"].waitForExistence(timeout: 2))

        app.textFields["Message 1"].click()
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO (message 1)"].waitForExistence(timeout: 2))
        XCTAssertEqual(second.value as? String, "SECOND")

        second.click()
        second.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.otherElements["Fan preview, message 3, empty"].waitForExistence(timeout: 2), "Tab moves to the next field")
    }

    @MainActor
    func testLightAppearanceRendersTheSameControls() throws {
        let app = launch(light: true, seed: ["Hello World. I hold 8 Msg.", "", "I'm your *NOTE PAD*", "*Mom Pick me up @4P*", "", "", "HELLO WILLIE", ""])
        XCTAssertTrue(app.otherElements["Fan preview showing Hello World. I hold 8 Msg. (message 1)"].waitForExistence(timeout: 3))
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Layout light")
    }

    @MainActor
    func testDarkAppearanceWithSeveralFieldsFilled() throws {
        let app = launch(seed: ["Hello World. I hold 8 Msg.", "", "I'm your *NOTE PAD*", "*Mom Pick me up @4P*", "", "", "HELLO WILLIE", ""])
        XCTAssertTrue(app.otherElements["Fan preview showing Hello World. I hold 8 Msg. (message 1)"].waitForExistence(timeout: 3))
        app.textFields["Message 4"].click()
        // A literal comparison: the subscript treats the asterisks in this label as a pattern.
        let preview = app.otherElements.matching(NSPredicate(format: "label == %@", "Fan preview showing *Mom Pick me up @4P* (message 4)")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        app.buttons["Connect to the fan"].click()
        XCTAssertTrue(app.staticTexts["Simulated fan: Connected"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Layout dark filled")
    }

    // MARK: - Scrolling evidence (Milestone 3)

    @MainActor
    func testALongMessageScrolls() throws {
        let app = launch(columnsPerRevolution: 120)
        replaceText(in: app.textFields["Message 1"], with: twentySixCharacters)
        XCTAssertTrue(app.otherElements["Fan preview showing \(twentySixCharacters) (message 1), scrolling"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testAShortMessageStandsStill() throws {
        let app = launch(columnsPerRevolution: 120)
        XCTAssertTrue(app.otherElements["Fan preview showing HELLO (message 1)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["Fan preview showing HELLO (message 1), scrolling"].exists)
    }

    // MARK: - Helpers

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
