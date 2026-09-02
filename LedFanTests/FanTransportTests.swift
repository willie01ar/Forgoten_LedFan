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
        try await transport.store(message("ONE", slot: 0))
        try await transport.store(message("TWO", slot: 1))
        try await transport.store(message("THREE", slot: 0))

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
        try await transport.store(message)

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

    @Test func theHardwareTransportSaysItCannotStoreMessages() {
        let transport = HIDFanTransport()
        guard case .unavailable(let reason) = transport.storeAvailability else {
            Issue.record("expected the hardware transport to be unavailable for storing")
            return
        }
        #expect(reason == FanTransportError.protocolNotYetKnown.localizedDescription)
        #expect(!reason.lowercased().contains("cable"))
    }

    @Test func storingOnDisconnectedHardwareThrowsNotConnected() async throws {
        let transport = HIDFanTransport()
        let message = try message()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.store(message)
        }
    }

    // MARK: - Errors

    @Test func everyTransportErrorHasAHumanReadableDescription() {
        let errors: [FanTransportError] = [
            .deviceNotFound, .openFailed(code: -1), .notConnected, .writeFailed(code: -2),
            .protocolNotYetKnown, .writingDisabled
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

    @Test func theUnknownProtocolMessageDoesNotBlameTheUser() {
        let message = FanTransportError.protocolNotYetKnown.localizedDescription.lowercased()
        #expect(message.contains("isn't known yet"))
        #expect(!message.contains("cable"))
        #expect(!message.contains("check"))
    }
}
