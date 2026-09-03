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
            try await transport.store(message)
        }
    }

    @Test func connectingThenStoringSucceedsAndIsRetainedPerSlot() async throws {
        let transport = SimulatedFanTransport()
        try await transport.connect()
        let receipt = try await transport.store(message("ONE", slot: 0))
        #expect(receipt.summary == "Stored in slot 1 on the simulated fan.")
        #expect(receipt.acknowledged)
        _ = try await transport.store(message("TWO", slot: 1))
        _ = try await transport.store(message("THREE", slot: 0))

        #expect(await transport.message(inSlot: 0)?.text == "THREE")
        #expect(await transport.message(inSlot: 1)?.text == "TWO")
        #expect(await transport.message(inSlot: 2) == nil)
    }

    @Test func disconnectingWithoutConnectingDoesNotTrap() async throws {
        let transport = SimulatedFanTransport()
        await transport.disconnect()
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store(message)
        }
    }

    @Test func storedMessagesAreObservable() async throws {
        let transport = SimulatedFanTransport()
        let message = try message("HI", slot: 4)
        try await transport.connect()
        _ = try await transport.store(message)

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

    @Test func theHardwareTransportSaysWhatToExpect() {
        let transport = HIDFanTransport(packetLogDirectory: nil)
        guard case .experimental(let caveat) = transport.storeAvailability else {
            Issue.record("expected the hardware transport to be experimental")
            return
        }
        #expect(caveat.contains("different generation"))
        #expect(caveat.contains("nothing is expected to appear"))
        #expect(!caveat.lowercased().contains("cable"))
    }

    @Test func storingOnDisconnectedHardwareThrowsNotConnected() async throws {
        let transport = HIDFanTransport(packetLogDirectory: nil)
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store(message)
        }
    }

    @Test func theReceiptSaysWhatHappenedAndNeverClaimsSuccess() {
        let plain = HIDFanTransport.receiptSummary(reportCount: 6, byteCount: 48, heldWrites: 0)
        let held = HIDFanTransport.receiptSummary(reportCount: 6, byteCount: 48, heldWrites: 1)
        #expect(plain.contains("6 reports"))
        #expect(plain.contains("48 bytes"))
        #expect(plain.contains("No acknowledgement"))
        #expect(plain.contains("Nothing is expected on the blades"))
        #expect(held.contains("1 write was held"))
        for copy in [plain, held, HIDFanTransport.caveat] {
            #expect(!Self.hasUnqualifiedSuccessLanguage(copy), "copy reads as success: \(copy)")
        }
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
            .deviceNotFound, .openFailed(code: -1), .notConnected, .writeFailed(code: -2),
            .nothingToStore, .tableTooLarge(bytes: 3000, limit: 2048)
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
