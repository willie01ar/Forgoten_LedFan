import Foundation

/// How a fan is laid out: LEDs along the arm, columns around one revolution.
nonisolated struct FanGeometry: Sendable, Equatable {
    let ledsPerArm: Int
    let columnsPerRevolution: Int

    /// Preview geometry (D1, D5). 180 columns is what makes text legible on screen; it says
    /// nothing about the hardware, whose column count is unknown.
    static let preview = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)
}

/// A message rendered to columns, bit 0 at the top of each glyph. Any length; may exceed
/// one revolution. Geometry-free by design (D1).
nonisolated struct ColumnStrip: Sendable, Equatable {
    let ledsPerArm: Int
    let columns: [UInt16]

    var isEmpty: Bool { columns.isEmpty }

    static func empty(ledsPerArm: Int) -> ColumnStrip {
        ColumnStrip(ledsPerArm: max(0, ledsPerArm), columns: [])
    }
}
