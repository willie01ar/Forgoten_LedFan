import Foundation
import Testing
@testable import LedFan

struct EEPROMWriterTests {
    private let writer = EEPROMWriter()

    @Test func everyPacketIsEightBytesAndStartsWithTheBlockZeroHeader() {
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

    @Test func nothingToWriteProducesNoPackets() {
        #expect(writer.packets(writing: [], toAddress: 0x40).isEmpty)
    }

    // MARK: - The 2 KB store: eight blocks, no packet across a block boundary

    @Test func blocksAboveTheFirstUseTheirOwnHeader() {
        #expect(EEPROMWriter.header(forBlock: 0) == 0xA0)
        #expect(EEPROMWriter.header(forBlock: 1) == 0xA2)
        #expect(EEPROMWriter.header(forBlock: 7) == 0xAE)
        let packets = writer.packets(writing: [1, 2, 3], toAddress: 0x100)
        #expect(packets == [[0xA2, 0x00, 1, 2, 3, 0, 0, 0]])
    }

    @Test func aChunkStopsAtABlockBoundaryAndContinuesInTheNext() {
        let packets = writer.packets(writing: Array(1...8), toAddress: 0xFE)
        #expect(packets.count == 2)
        #expect(packets[0] == [0xA0, 0xFE, 1, 2, 0, 0, 0, 0])
        #expect(packets[1] == [0xA2, 0x00, 3, 4, 5, 6, 7, 8])
    }

    @Test func aFullTableSpansTheStoreInOrder() {
        let packets = writer.packets(writing: [UInt8](repeating: 0x55, count: 2048), toAddress: 0)
        #expect(packets.count == 8 * 43, "each 256-byte block is 42 full packets plus one of 4 bytes")
        #expect(Set(packets.map { $0[0] }) == [0xA0, 0xA2, 0xA4, 0xA6, 0xA8, 0xAA, 0xAC, 0xAE])
    }

    @Test func theStallProneRangeIsTheOneTheFirmwareShowed() {
        #expect(EEPROMWriter.stallProneAddresses == 0x18...0x23)
    }
}
