import Foundation
import Testing
@testable import LedFan

struct FanTransportTests {
    private let rasterizer = ColumnRasterizer()

    // MARK: - Simulated transport

    @Test func displayingBeforeConnectingThrows() async {
        let transport = SimulatedFanTransport(ledsPerArm: 11)
        let frame = rasterizer.frame(for: "HI", ledsPerArm: 11)

        await #expect(throws: FanTransportError.notConnected) {
            try await transport.display(frame)
        }
    }

    @Test func connectingThenDisplayingSucceeds() async throws {
        let transport = SimulatedFanTransport(ledsPerArm: 11)
        try await transport.connect()
        try await transport.display(rasterizer.frame(for: "HI", ledsPerArm: 11))
    }

    @Test func disconnectingWithoutConnectingDoesNotTrap() async {
        let transport = SimulatedFanTransport(ledsPerArm: 11)
        await transport.disconnect()
        await #expect(throws: FanTransportError.notConnected) {
            try await transport.display(rasterizer.frame(for: "HI", ledsPerArm: 11))
        }
    }

    @Test func displayedFramesAreObservable() async throws {
        let transport = SimulatedFanTransport(ledsPerArm: 11)
        let frame = rasterizer.frame(for: "HI", ledsPerArm: 11)
        try await transport.connect()
        try await transport.display(frame)

        var frames = transport.frames.makeAsyncIterator()
        #expect(await frames.next() == frame)
    }

    @Test func reportedArmLengthMatchesConfiguration() async {
        let transport = SimulatedFanTransport(ledsPerArm: 7)
        #expect(await transport.ledsPerArm == 7)
    }

    // MARK: - Packet encoder

    @Test func encoderPacksColumnsIntoEightByteReports() throws {
        let frame = rasterizer.frame(for: "A", ledsPerArm: 11)
        let packets = try SequencedColumnEncoder().packets(for: frame)

        #expect(packets.allSatisfy { $0.count == SequencedColumnEncoder.reportSize })
        #expect(packets.count == 2)
        #expect(packets[0][0] == 0)
        #expect(packets[1][0] == 1)
    }

    @Test func encoderPacketCountMatchesColumnDensity() throws {
        let frame = POVFrame(ledsPerArm: 11, columns: [UInt16](repeating: 1, count: 7))
        let packets = try SequencedColumnEncoder().packets(for: frame)

        #expect(packets.count == 3)
        #expect(packets.allSatisfy { $0.count == SequencedColumnEncoder.reportSize })
    }

    @Test func encoderPadsAShortFinalPacketWithZeros() throws {
        let frame = POVFrame(ledsPerArm: 11, columns: [0x0102, 0x0304, 0x0506, 0x0708])
        let packets = try SequencedColumnEncoder().packets(for: frame)

        #expect(packets[0] == [0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0])
        #expect(packets[1] == [1, 0x07, 0x08, 0, 0, 0, 0, 0])
    }

    @Test func encoderNumbersPacketsSequentiallyAndWrapsAtOneByte() throws {
        let columnCount = SequencedColumnEncoder.columnsPerPacket * 300
        let frame = POVFrame(ledsPerArm: 11, columns: [UInt16](repeating: 1, count: columnCount))
        let packets = try SequencedColumnEncoder().packets(for: frame)

        #expect(packets.count == 300)
        for (index, packet) in packets.enumerated() {
            #expect(packet[0] == UInt8(index % 256))
        }
    }

    @Test func encoderRejectsAnEmptyFrame() {
        #expect(throws: FanTransportError.protocolNotYetKnown) {
            try SequencedColumnEncoder().packets(for: .empty)
        }
    }

    // MARK: - Errors

    @Test func everyTransportErrorHasAHumanReadableDescription() {
        let errors: [FanTransportError] = [
            .deviceNotFound, .openFailed(code: -1), .notConnected, .writeFailed(code: -2), .protocolNotYetKnown
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
}
