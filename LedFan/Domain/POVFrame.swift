import Foundation

/// Exactly one revolution of the fan. `columns.count == geometry.columnsPerRevolution`,
/// always: the initialiser pads or truncates to keep it so. Bit 0 is the innermost LED.
nonisolated struct POVFrame: Sendable, Equatable {
    let geometry: FanGeometry
    let columns: [UInt16]

    init(geometry: FanGeometry, columns: [UInt16]) {
        self.geometry = geometry
        let count = max(0, geometry.columnsPerRevolution)
        if columns.count >= count {
            self.columns = Array(columns.prefix(count))
        } else {
            self.columns = columns + [UInt16](repeating: 0, count: count - columns.count)
        }
    }

    static func blank(geometry: FanGeometry) -> POVFrame {
        POVFrame(geometry: geometry, columns: [])
    }

    var isBlank: Bool { columns.allSatisfy { $0 == 0 } }
    var litColumnCount: Int { columns.count { $0 != 0 } }
}
