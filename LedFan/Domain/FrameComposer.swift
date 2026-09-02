import Foundation

nonisolated protocol FrameComposing: Sendable {
    /// `columnOffset` is the disc column where the strip's first column lands, positive in
    /// the sweep direction. Any integer; it wraps.
    func frame(from strip: ColumnStrip, geometry: FanGeometry, columnOffset: Int) -> POVFrame
}

/// Lays the strip on a ring at least one revolution long, dark where the strip ends, then
/// reads one revolution off that ring. A strip longer than a revolution wraps, so scrolling
/// is a change of `columnOffset` (D1). Glyph rows run top-down from bit 0 while LEDs run
/// hub-outward from bit 0; upright text on the upper arc needs glyph tops at the rim, so
/// every column is mirrored along the arm.
nonisolated struct RevolutionComposer: FrameComposing {
    func frame(from strip: ColumnStrip, geometry: FanGeometry, columnOffset: Int) -> POVFrame {
        let revolution = geometry.columnsPerRevolution
        guard revolution > 0 else { return .blank(geometry: geometry) }

        let ringLength = max(strip.columns.count, revolution)
        let ring = strip.columns + [UInt16](repeating: 0, count: ringLength - strip.columns.count)

        let columns = (0..<revolution).map { discColumn in
            let ringIndex = Self.wrap(discColumn - columnOffset, modulo: ringLength)
            return Self.mirror(ring[ringIndex], ledsPerArm: geometry.ledsPerArm)
        }
        return POVFrame(geometry: geometry, columns: columns)
    }

    // MARK: - Helpers

    private static func wrap(_ value: Int, modulo length: Int) -> Int {
        let remainder = value % length
        return remainder < 0 ? remainder + length : remainder
    }

    private static func mirror(_ column: UInt16, ledsPerArm: Int) -> UInt16 {
        guard ledsPerArm > 0 else { return 0 }
        var mirrored: UInt16 = 0
        for led in 0..<min(ledsPerArm, 16) where column & (1 << UInt16(led)) != 0 {
            mirrored |= 1 << UInt16(ledsPerArm - 1 - led)
        }
        return mirrored
    }
}
