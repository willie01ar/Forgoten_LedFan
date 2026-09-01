import Foundation

/// One revolution of the fan, as vertical LED columns. Bit 0 is the innermost LED.
nonisolated struct POVFrame: Sendable, Equatable {
    let ledsPerArm: Int
    let columns: [UInt16]

    static let empty = POVFrame(ledsPerArm: 0, columns: [])

    var isEmpty: Bool { columns.isEmpty }
}
