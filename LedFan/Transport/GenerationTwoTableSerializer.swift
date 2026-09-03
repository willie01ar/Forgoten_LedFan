import Foundation

/// Serialises the message table the display firmware parses.
nonisolated protocol MessageTableSerializing: Sendable {
    func bytes(for messages: [FanMessage]) throws -> [UInt8]
}

/// The message table of the **generation-2** SONiX fans (`0c45:7160`, 11 LEDs), recovered
/// byte for byte from the vendor editor's serializer (protocol-findings.md, Slice 5, Task 1).
/// Our head, `0c45:7701`, appears to be a later generation and ignored this table wherever
/// it was written; this type exists to make the write path real and tested, not to light
/// the disc (D16). It rasterises through the injected rasterizer: the host draws, the fan
/// only stores (D13).
///
/// Stream: `00`, `0x80 | count`, then per message `[columns+2] 00 [style] [open<<4|close] 00 00`,
/// the characters' columns last to first as little-endian words, `00 00`; eight `00` after
/// the last message. A column word carries the pixels in bits 0–10 and the colour in bit 13,
/// as in the sibling's captured uploads; the vendor's own font tables use other rotations
/// and its mode-1 permutation was never decoded, so this is the one layout with a capture
/// behind it.
nonisolated struct GenerationTwoTableSerializer: MessageTableSerializing {
    static let ledsPerArm = 11
    static let storeCapacity = 2048          // the vendor's "IC ROM Over" ceiling
    static let pixelMask: UInt16 = 0x07FF
    static let colourFlag: UInt16 = 0x2000    // red, in the sibling's colour bits 13–15
    static let trailingZeros = 8

    /// Effect vocabulary from the vendor UI: style 3 is "Remain"; 0 is "from left to right"
    /// for opening and "from right to left" for closing.
    let style: UInt8
    let openingEffect: UInt8
    let closingEffect: UInt8
    private let rasterizer: any MessageRasterizing

    init(rasterizer: any MessageRasterizing = ColumnRasterizer(), style: UInt8 = 3, openingEffect: UInt8 = 0, closingEffect: UInt8 = 0) {
        self.rasterizer = rasterizer
        self.style = style
        self.openingEffect = openingEffect & 0x0F
        self.closingEffect = closingEffect & 0x0F
    }

    func bytes(for messages: [FanMessage]) throws -> [UInt8] {
        let nonEmpty = messages.filter { !$0.text.isEmpty }
        guard !nonEmpty.isEmpty else { throw FanTransportError.nothingToStore }

        var stream: [UInt8] = [0x00, 0x80 | UInt8(nonEmpty.count & 0x7F)]
        for message in nonEmpty {
            stream += table(for: message)
        }
        stream += [UInt8](repeating: 0, count: Self.trailingZeros)

        guard stream.count <= Self.storeCapacity else {
            throw FanTransportError.tableTooLarge(bytes: stream.count, limit: Self.storeCapacity)
        }
        return stream
    }

    // MARK: - Helpers

    private func table(for message: FanMessage) -> [UInt8] {
        let columns = rasterizer.strip(for: message.text, ledsPerArm: Self.ledsPerArm).columns
        var bytes: [UInt8] = [UInt8(truncatingIfNeeded: columns.count + 2), 0x00, style, (openingEffect << 4) | closingEffect, 0x00, 0x00]
        for column in columns.reversed() {
            let word = (column & Self.pixelMask) | Self.colourFlag
            bytes += [UInt8(word & 0xFF), UInt8(word >> 8)]
        }
        return bytes + [0x00, 0x00]
    }
}
