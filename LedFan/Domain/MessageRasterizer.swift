import Foundation

nonisolated protocol MessageRasterizing: Sendable {
    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip
}

/// Lays glyphs left to right and centres them vertically on the arm. Knows nothing about
/// revolutions or angles; that is the composer's job.
nonisolated struct ColumnRasterizer: MessageRasterizing {
    let letterSpacing: Int

    init(letterSpacing: Int = 1) {
        self.letterSpacing = max(0, letterSpacing)
    }

    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip {
        guard ledsPerArm > 0, !text.isEmpty else { return .empty(ledsPerArm: ledsPerArm) }

        let verticalOffset = max(0, (ledsPerArm - GlyphFont.glyphHeight) / 2)
        let spacing = [UInt16](repeating: 0, count: letterSpacing)

        let columns = text.flatMap { character in
            GlyphFont.columns(for: character).map { shift($0, by: verticalOffset, limitedTo: ledsPerArm) } + spacing
        }
        return ColumnStrip(ledsPerArm: ledsPerArm, columns: columns)
    }

    // MARK: - Helpers

    private func shift(_ column: UInt8, by offset: Int, limitedTo ledsPerArm: Int) -> UInt16 {
        let mask: UInt16 = ledsPerArm >= 16 ? .max : (1 << UInt16(ledsPerArm)) - 1
        return (UInt16(column) << UInt16(offset)) & mask
    }
}
