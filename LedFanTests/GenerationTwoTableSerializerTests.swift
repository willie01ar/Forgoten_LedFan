import Foundation
import Testing
@testable import LedFan

/// Emits a fixed column per character so the expected bytes can be written by hand.
nonisolated struct StubRasterizer: MessageRasterizing {
    let columnsPerCharacter: [UInt16]

    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip {
        ColumnStrip(ledsPerArm: ledsPerArm, columns: text.flatMap { _ in columnsPerCharacter })
    }
}

struct GenerationTwoTableSerializerTests {
    private func message(_ text: String, slot: Int = 0) throws -> FanMessage { try FanMessage(slot: slot, text: text) }

    // MARK: - Byte-for-byte against protocol-findings.md, Slice 5, Task 1

    @Test func oneMessageMatchesTheVendorStreamByteForByte() throws {
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: [0x0001, 0x0002, 0x0400]))
        let bytes = try serializer.bytes(for: [message("X")])

        let expected: [UInt8] = [
            0x00, 0x81,                          // global header: 00, then 0x80 | count
            0x05, 0x00, 0x03, 0x00, 0x00, 0x00,  // columns+2 = 3+2, 00, style 3 (remain), open<<4|close, 00 00
            0x00, 0x24,                          // columns LAST to FIRST, little-endian, colour bit 13 set: 0x2400
            0x02, 0x20,                          // 0x2002
            0x01, 0x20,                          // 0x2001
            0x00, 0x00,                          // end of message
            0, 0, 0, 0, 0, 0, 0, 0               // eight trailing zeros
        ]
        #expect(bytes == expected)
    }

    @Test func theCountByteCarriesTheNumberOfNonEmptyMessages() throws {
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: [0x0001]))
        let bytes = try serializer.bytes(for: [message("A", slot: 0), message("", slot: 1), message("B", slot: 2)])
        #expect(bytes[0] == 0x00)
        #expect(bytes[1] == 0x82, "two messages; the empty one is skipped, as the vendor does")
        // second message header starts after the first: 2 + (6 + 2 + 2)
        #expect(bytes[12] == 0x03, "columns+2 of the second message")
    }

    @Test func columnsPlusTwoIsTheMessageLengthField() throws {
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: [0x0001, 0x0001]))
        let bytes = try serializer.bytes(for: [message("ABCDE")])   // 5 characters x 2 columns
        #expect(bytes[2] == 12)
    }

    @Test func effectsArePackedOpenHighCloseLow() throws {
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: [0x0001]), style: 2, openingEffect: 8, closingEffect: 5)
        let bytes = try serializer.bytes(for: [message("A")])
        #expect(bytes[4] == 0x02)
        #expect(bytes[5] == 0x85)
    }

    @Test func charactersAreEmittedLastToFirst() throws {
        // Two characters, one column each; the stub gives every character the same column,
        // so use a real rasterizer with distinct glyphs and compare against its own strip.
        let rasterizer = ColumnRasterizer()
        let serializer = GenerationTwoTableSerializer(rasterizer: rasterizer)
        let bytes = try serializer.bytes(for: [message("AB")])
        let columns = rasterizer.strip(for: "AB", ledsPerArm: 11).columns
        var expectedColumnBytes: [UInt8] = []
        for column in columns.reversed() {
            let word = (column & 0x07FF) | 0x2000
            expectedColumnBytes += [UInt8(word & 0xFF), UInt8(word >> 8)]
        }
        #expect(Array(bytes[8..<8 + expectedColumnBytes.count]) == expectedColumnBytes)
    }

    @Test func pixelBitsAboveTenAreMaskedAndTheColourBitIsAlwaysSet() throws {
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: [0xFFFF, 0x0000]))
        let bytes = try serializer.bytes(for: [message("A")])
        // reversed: 0x0000 -> 0x2000, then 0xFFFF -> 0x27FF
        #expect(Array(bytes[8..<12]) == [0x00, 0x20, 0xFF, 0x27])
    }

    @Test func aMessageBeyondTheStoreIsRefusedNotTruncated() throws {
        // 26 characters x 40 columns x 2 bytes is well over 2 KB.
        let serializer = GenerationTwoTableSerializer(rasterizer: StubRasterizer(columnsPerCharacter: Array(repeating: 1, count: 40)))
        #expect(throws: FanTransportError.tableTooLarge(bytes: 2 + 6 + 26 * 80 + 2 + 8, limit: 2048)) {
            try serializer.bytes(for: [message("THE QUICK BROWN FOX JUMPS!")])
        }
    }

    @Test func aRealTwentySixCharacterMessageFitsTheStore() throws {
        let bytes = try GenerationTwoTableSerializer().bytes(for: [message("THE QUICK BROWN FOX JUMPS!")])
        #expect(bytes.count == 2 + 6 + 156 * 2 + 2 + 8)
        #expect(bytes.count <= GenerationTwoTableSerializer.storeCapacity)
    }

    @Test func onlyEmptyMessagesIsAnErrorNotAnEmptyTable() {
        #expect(throws: FanTransportError.nothingToStore) {
            try GenerationTwoTableSerializer().bytes(for: [try FanMessage(slot: 0, text: "")])
        }
    }

    @Test func serialisationIsPure() throws {
        let serializer = GenerationTwoTableSerializer()
        let messages = [try message("HELLO", slot: 0), try message("WORLD", slot: 3)]
        #expect(try serializer.bytes(for: messages) == (try serializer.bytes(for: messages)))
    }
}
