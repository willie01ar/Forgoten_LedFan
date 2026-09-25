import Foundation

/// The protocol of the PEARL PX5939 / PowerTRC fan, SONiX `0c45:7701`: our head. Reimplemented
/// from the facts in pearlfan-rs (MIT/Apache-2.0, github.com/mwja/pearlfan-rs); see
/// docs/protocol-findings.md, Slice 9, for the byte-level map with source citations. No code
/// from Ventto/pearlfan (GPLv3) is used.
///
/// Per message: one header report, then 39 data reports of four 16-bit columns each, 156
/// columns of 11 pixels. A column word starts all ones and a lit pixel CLEARS its bit; the
/// last column on the wire is the leftmost on the disc. Rasterises through the injected
/// rasterizer at 11 LEDs; a message wider than 156 columns is refused, never cut.
nonisolated struct PearlFanEncoder: FanReportEncoding {
    static let ledsPerArm = 11
    static let columnsPerImage = 156
    static let columnsPerReport = 4
    static let reportsPerImage = 1 + columnsPerImage / columnsPerReport   // header + 39
    static let headerConstant: UInt64 = 0x0000_0055_0000_10A0
    static let blankColumn: UInt16 = 0xFFFF

    /// Which bit of a column word each image row clears, row 0 at the top of the arm.
    static let ledBits: [UInt16] = [0x0008, 0x0004, 0x0002, 0x0001, 0x8000, 0x4000,
                                    0x2000, 0x1000, 0x0800, 0x0400, 0x0200]

    let effects: PearlFanEffects
    private let rasterizer: any MessageRasterizing

    init(rasterizer: any MessageRasterizing = ColumnRasterizer(), effects: PearlFanEffects = .remain) {
        self.rasterizer = rasterizer
        self.effects = effects
    }

    func reports(for messages: [FanMessage]) throws -> [[UInt8]] {
        try messages.flatMap { message in
            let strip = rasterizer.strip(for: message.text, ledsPerArm: Self.ledsPerArm)
            guard strip.columns.count <= Self.columnsPerImage else {
                throw FanTransportError.imageTooWide(columns: strip.columns.count, limit: Self.columnsPerImage)
            }
            return [effects.header(imageID: UInt8(message.slot))] + Self.dataReports(for: strip.columns)
        }
    }

    // MARK: - Helpers

    /// Column `x` on the disc becomes word `155 - x` on the wire; unused columns stay blank.
    private static func dataReports(for columns: [UInt16]) -> [[UInt8]] {
        let words = (0..<columnsPerImage).reversed().map { x in
            x < columns.count ? word(for: columns[x]) : blankColumn
        }
        return stride(from: 0, to: words.count, by: columnsPerReport).map { start in
            words[start..<start + columnsPerReport].flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        }
    }

    private static func word(for column: UInt16) -> UInt16 {
        var word = blankColumn
        for (row, bit) in ledBits.enumerated() where column & (1 << UInt16(row)) != 0 {
            word &= ~bit
        }
        return word
    }
}

/// The header's effect fields, with the reference driver's codes. Where the vendor UI's
/// vocabulary applies it is named; "remain" (no motion before closing) is the default.
nonisolated struct PearlFanEffects: Sendable, Equatable {
    enum Transition: UInt16, Sendable, CaseIterable {
        case rightToLeft = 0, leftToRight = 1, symmetric = 2, redCarpet = 3
        case topToBottom = 4, bottomToTop = 5
        /// Skips the transition. Valid for opening only.
        case fastMode = 6
    }

    enum Motion: UInt16, Sendable, CaseIterable {
        case remain = 0
        case clockwise = 2          // "turn left to right"
        case anticlockwise = 6      // "turn right to left"
    }

    let open: Transition
    let close: Transition
    let beforeClose: Motion

    static let remain = PearlFanEffects(open: .rightToLeft, close: .rightToLeft, beforeClose: .remain)

    init(open: Transition = .rightToLeft, close: Transition = .rightToLeft, beforeClose: Motion = .remain) {
        self.open = open
        self.close = close == .fastMode ? .rightToLeft : close
        self.beforeClose = beforeClose
    }

    /// `A0 10 <close | open<<4> <id | beforeClose<<4> 55 00 00 00`: the 64-bit constant with
    /// the 16-bit options field at bits 16–31, little-endian on the wire.
    func header(imageID: UInt8) -> [UInt8] {
        let options = close.rawValue | open.rawValue << 4 | UInt16(imageID & 0x0F) << 8 | beforeClose.rawValue << 12
        let value = PearlFanEncoder.headerConstant | UInt64(options) << 16
        return (0..<8).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
    }
}
