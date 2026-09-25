import Foundation
import Testing
@testable import LedFan

/// Task 4: a deliberately trivial format, test target only. If the stack accepts it
/// unchanged, a future Version-3 conformance slots in the same way.
nonisolated struct TrivialTableSerializer: MessageTableSerializing {
    func bytes(for messages: [FanMessage]) throws -> [UInt8] {
        messages.flatMap { [UInt8($0.slot)] + Array($0.text.utf8) }
    }
}

struct FanTableWriterTests {
    @Test func theSeamAcceptsAnyFormatWithoutChangingTheFraming() throws {
        let writer = FanTableWriter(serializer: TrivialTableSerializer())
        let reports = try writer.reports(for: [try FanMessage(slot: 2, text: "HI")])
        #expect(reports == [[0xA0, 0x00, 0x02, 0x48, 0x49, 0, 0, 0]])
    }

    @Test func theProductionWriterFramesTheGenerationTwoTable() throws {
        let writer = FanTableWriter()
        let message = try FanMessage(slot: 0, text: "A")
        let table = try GenerationTwoTableSerializer().bytes(for: [message])
        let reports = try writer.reports(for: [message])
        #expect(reports.count == (table.count + 5) / 6)
        #expect(reports.first?[0] == 0xA0)
        #expect(Array(reports[0][2...7]) == Array(table[0..<6]))
    }

    @Test func serializerErrorsPassThroughUntouched() {
        let writer = FanTableWriter()
        #expect(throws: FanTransportError.nothingToStore) {
            try writer.reports(for: [try FanMessage(slot: 0, text: "")])
        }
    }

    @Test func thePacketLogReproducesASendLineForLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LedFanTests-log-\(UUID().uuidString)")
        let log = PacketLog(directory: directory)
        let reports: [[UInt8]] = [[0xA0, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06], [0xA0, 0x06, 0xFF, 0, 0, 0, 0, 0]]
        let url = try log.write(reports, label: "slot1", at: Date(timeIntervalSince1970: 0))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "A0 00 01 02 03 04 05 06\nA0 06 FF 00 00 00 00 00\n")
        #expect(url.lastPathComponent.hasSuffix("-slot1.hex"))
    }

    @Test func thePacketLogRecordsEachAcknowledgementOrItsAbsence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LedFanTests-log-\(UUID().uuidString)")
        let reports: [[UInt8]] = [[0xA0, 0x10, 0, 0, 0x55, 0, 0, 0], [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]]
        let url = try PacketLog(directory: directory).write(reports, acknowledgements: [[0x01, 0x02], nil], label: "slot1")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "A0 10 00 00 55 00 00 00  <- 01 02\nFF FF FF FF FF FF FF FF  <- no acknowledgement\n")
    }

    @Test func theHardwareDefaultIsThePearlFanProtocolAndGenerationTwoStaysSelectable() throws {
        let message = try FanMessage(slot: 0, text: "A")
        let pearl = try PearlFanEncoder().reports(for: [message])
        let generationTwo = try FanTableWriter().reports(for: [message])
        #expect(pearl.count == 40)
        #expect(pearl[0][0] == 0xA0 && pearl[0][1] == 0x10)
        #expect(generationTwo[0][0] == 0xA0 && generationTwo[0][1] == 0x00)
        _ = HIDFanTransport(encoder: FanTableWriter(), packetLogDirectory: nil)
    }
}
