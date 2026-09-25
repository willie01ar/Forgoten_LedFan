import Foundation
import Testing
@testable import LedFan

struct FanTransportTests {
    private func message(_ text: String = "HI", slot: Int = 0) throws -> FanMessage {
        try FanMessage(slot: slot, text: text)
    }

    // MARK: - Simulated transport

    @Test func storingBeforeConnectingThrows() async throws {
        let transport = SimulatedFanTransport()
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store([message])
        }
    }

    @Test func connectingThenStoringSucceedsAndIsRetainedPerSlot() async throws {
        let transport = SimulatedFanTransport()
        try await transport.connect()
        let receipt = try await transport.store([message("ONE", slot: 0), message("TWO", slot: 1)])
        #expect(receipt.summary == "Stored 2 slots on the simulated fan, 2 with text.")
        _ = try await transport.store([message("THREE", slot: 0)])

        #expect(await transport.message(inSlot: 0)?.text == "THREE")
        #expect(await transport.message(inSlot: 1) == nil, "a store replaces the whole set, like the fan")
        #expect(await transport.message(inSlot: 2) == nil)
    }

    @Test func disconnectingWithoutConnectingDoesNotTrap() async throws {
        let transport = SimulatedFanTransport()
        await transport.disconnect()
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store([message])
        }
    }

    @Test func storedMessagesAreObservable() async throws {
        let transport = SimulatedFanTransport()
        let message = try message("HI", slot: 4)
        try await transport.connect()
        _ = try await transport.store([message])

        var stored = transport.storedMessages.makeAsyncIterator()
        #expect(await stored.next() == message)
    }

    @Test func reportedGeometryMatchesConfiguration() async {
        let geometry = FanGeometry(ledsPerArm: 7, columnsPerRevolution: 90)
        let transport = SimulatedFanTransport(geometry: geometry)
        #expect(await transport.geometry == geometry)
        #expect(transport.storeAvailability == .available)
    }

    // MARK: - Hardware transport, without hardware

    @Test func theHardwareTransportSaysHowToProgram() {
        let transport = HIDFanTransport(packetLogDirectory: nil)
        guard case .experimental(let caveat) = transport.storeAvailability else {
            Issue.record("expected the hardware transport to be experimental")
            return
        }
        #expect(caveat.contains("PearlFan protocol"))
        #expect(caveat.contains("switched off"))
        #expect(caveat.contains("swap to the power cable"))
    }

    @Test func storingOnDisconnectedHardwareThrowsNotConnected() async throws {
        let transport = HIDFanTransport(packetLogDirectory: nil)
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store([message])
        }
    }

    @Test func theReceiptSaysWhatHappenedAndNeverClaimsSuccess() {
        let all = HIDFanTransport.receiptSummary(messageCount: 8, reportCount: 320, byteCount: 2560,
                                                 verification: EchoVerification(confirmed: 320, mismatched: 0, missing: 0), elapsed: .seconds(5))
        let some = HIDFanTransport.receiptSummary(messageCount: 8, reportCount: 320, byteCount: 2560,
                                                  verification: EchoVerification(confirmed: 300, mismatched: 5, missing: 15), elapsed: .milliseconds(20300))
        let none = HIDFanTransport.receiptSummary(messageCount: 8, reportCount: 320, byteCount: 2560,
                                                  verification: EchoVerification(confirmed: 0, mismatched: 0, missing: 320), elapsed: .seconds(320))
        #expect(all.contains("Published all 8 slots"))
        #expect(all.contains("320 reports"))
        #expect(all.contains("Every report was confirmed by the fan's echo"))
        #expect(some.contains("300 of 320 reports confirmed by echo; 5 differed, 15 missing"))
        #expect(none.contains("No echo came back"))
        for copy in [all, some, none, HIDFanTransport.caveat] {
            #expect(!Self.hasUnqualifiedSuccessLanguage(copy), "copy reads as success: \(copy)")
        }
    }

    @Test func theUnpluggedCopySaysWhatToDoAndDoesNotBlameTheWrite() {
        let copy = FanTransportError.deviceRemoved.localizedDescription
        #expect(copy.contains("unplugged"))
        #expect(copy.contains("Connect again"))
        #expect(!copy.lowercased().contains("rejected"))
    }

    /// "sent", "success", "done", "delivered" or "displayed" with nothing qualifying them.
    private static func hasUnqualifiedSuccessLanguage(_ copy: String) -> Bool {
        let lower = copy.lowercased()
        let banned = ["success", "done", "delivered", "displayed", "displaying", "now showing"]
        if banned.contains(where: { lower.contains($0) }) { return true }
        if lower.contains("sent") && !lower.contains("no acknowledgement") { return true }
        return false
    }

    // MARK: - Errors

    @Test func everyTransportErrorHasAHumanReadableDescription() {
        let errors: [FanTransportError] = [
            .deviceNotFound, .openFailed(code: -1), .notConnected, .deviceRemoved, .writeFailed(code: -2),
            .nothingToStore, .tableTooLarge(bytes: 3000, limit: 2048), .imageTooWide(columns: 157, limit: 156)
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.localizedDescription == error.errorDescription)
        }
    }

    @Test func missingDeviceMessageNamesThePowerCableTrap() {
        let message = FanTransportError.deviceNotFound.localizedDescription.lowercased()
        #expect(message.contains("data cable"))
        #expect(message.contains("power"))
    }

    @Test func theTooLargeMessageSaysNothingWasWritten() {
        let message = FanTransportError.tableTooLarge(bytes: 3000, limit: 2048).localizedDescription
        #expect(message.contains("3000"))
        #expect(message.contains("2048"))
        #expect(message.contains("Nothing was written"))
    }
}
