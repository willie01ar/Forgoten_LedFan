import Foundation

nonisolated protocol MessageRasterizing: Sendable {
    func frame(for text: String, ledsPerArm: Int) -> POVFrame
}

/// Lays glyphs left to right and centres them vertically on the arm.
nonisolated struct ColumnRasterizer: MessageRasterizing {
    let letterSpacing: Int

    init(letterSpacing: Int = 1) {
        self.letterSpacing = max(0, letterSpacing)
    }

    func frame(for text: String, ledsPerArm: Int) -> POVFrame {
        guard ledsPerArm > 0, !text.isEmpty else {
            return POVFrame(ledsPerArm: max(0, ledsPerArm), columns: [])
        }

        let verticalOffset = max(0, (ledsPerArm - GlyphFont.glyphHeight) / 2)
        let spacing = [UInt16](repeating: 0, count: letterSpacing)

        let columns = text.flatMap { character in
            GlyphFont.columns(for: character).map { shift($0, by: verticalOffset, limitedTo: ledsPerArm) } + spacing
        }
        return POVFrame(ledsPerArm: ledsPerArm, columns: columns)
    }

    // MARK: - Helpers

    private func shift(_ column: UInt8, by offset: Int, limitedTo ledsPerArm: Int) -> UInt16 {
        let mask: UInt16 = ledsPerArm >= 16 ? .max : (1 << UInt16(ledsPerArm)) - 1
        return (UInt16(column) << UInt16(offset)) & mask
    }
}
