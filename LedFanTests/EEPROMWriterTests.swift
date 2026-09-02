import Foundation
import Testing
@testable import LedFan

struct EEPROMWriterTests {
    private let writer = EEPROMWriter()

    @Test func everyPacketIsEightBytesAndStartsWithTheWriteHeader() {
        let packets = writer.packets(writing: Array(0..<40), toAddress: 0)
        #expect(!packets.isEmpty)
        #expect(packets.allSatisfy { $0.count == EEPROMWriter.reportSize })
        #expect(packets.allSatisfy { $0[0] == 0xA0 })
    }

    @Test func theAddressAdvancesByThePayloadOfEachPacket() {
        let packets = writer.packets(writing: Array(0..<14), toAddress: 0x10)
        #expect(packets.map { $0[1] } == [0x10, 0x16, 0x1C])
        #expect(packets[0][2...7] == [0, 1, 2, 3, 4, 5])
        #expect(packets[2][2...3] == [12, 13])
    }

    @Test func theFinalChunkIsZeroPadded() {
        let packets = writer.packets(writing: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11], toAddress: 0)
        #expect(packets.count == 2)
        #expect(packets[1] == [0xA0, 0x06, 0x11, 0, 0, 0, 0, 0])
    }

    @Test func aTwentySixCharacterPayloadNeedsFivePackets() {
        let payload = Array("THE QUICK BROWN FOX JUMPS!".utf8)
        #expect(payload.count == 26)
        #expect(writer.packets(writing: payload, toAddress: 0).count == 5)
    }

    @Test func aTwentySixCharacterColumnPayloadNeedsTwentySixPackets() {
        // 26 characters x 6 columns x 1 byte, if the table turned out to be column bytes.
        #expect(writer.packets(writing: [UInt8](repeating: 0, count: 156), toAddress: 0).count == 26)
    }

    @Test func nothingToWriteProducesNoPackets() {
        #expect(writer.packets(writing: [], toAddress: 0x40).isEmpty)
    }

    @Test func theAddressWrapsAtTheEndOfAnEightBitSpace() {
        let packets = writer.packets(writing: Array(repeating: 1, count: 12), toAddress: 0xFC)
        #expect(packets.map { $0[1] } == [0xFC, 0x02])
    }

    @Test func theStallProneRangeIsTheOneTheFirmwareShowed() {
        #expect(EEPROMWriter.stallProneAddresses == 0x18...0x23)
    }

    // MARK: - The unknown half

    @Test func theTableSerializerAdmitsTheFormatIsUnknown() throws {
        let message = try FanMessage(slot: 0, text: "HELLO")
        #expect(throws: FanTransportError.protocolNotYetKnown) {
            try UnknownMessageTableSerializer().bytes(for: [message])
        }
    }
}
