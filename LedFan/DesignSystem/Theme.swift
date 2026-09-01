import SwiftUI

enum Layout {
    static let tight: CGFloat = 8
    static let standard: CGFloat = 16
    static let loose: CGFloat = 24
    static let simulatorSide: CGFloat = 260
    static let ledDiameter: CGFloat = 4
    static let cornerRadius: CGFloat = 12
    static let minimumWindowWidth: CGFloat = 360
    static let shadowRadius: CGFloat = 12
}

enum Palette {
    static let litLED = Color.accentColor
    static let unlitLED = Color.primary.opacity(0.08)
    /// Unlit air, deliberately dark in both appearances.
    static let simulatorBackground = Color.black.opacity(0.85)
    static let simulatorShadow = Color.black.opacity(0.25)

    static let statusIdle = Color.secondary
    static let statusConnected = Color.green
    static let statusFailed = Color.red
    static let error = Color.red
}
