import SwiftUI

enum Layout {
    static let tight: CGFloat = 8
    static let standard: CGFloat = 16
    static let loose: CGFloat = 24
    static let simulatorSide: CGFloat = 340
    /// The LED band sits between these fractions of the disc's width, hub to tip.
    static let simulatorHubRatio: CGFloat = 0.27
    static let simulatorTipRatio: CGFloat = 0.47
    static let ledDiameter: CGFloat = 3.2
    static let cornerRadius: CGFloat = 12
    /// Wide enough for eight fields and their counters under the preview.
    static let minimumWindowWidth: CGFloat = 600
    static let idealWindowWidth: CGFloat = 900
    static let counterWidth: CGFloat = 52
    static let shadowRadius: CGFloat = 12
}

enum Palette {
    static let litLED = Color.accentColor
    static let unlitLED = Color.white.opacity(0.06)
    /// Unlit air, deliberately dark in both appearances.
    static let simulatorBackground = Color.black.opacity(0.85)
    static let simulatorShadow = Color.black.opacity(0.25)

    static let statusIdle = Color.secondary
    static let statusConnected = Color.green
    static let statusFailed = Color.red
    static let error = Color.red
    static let counterWithinLimit = Color.secondary
    static let counterOverLimit = Color.red
}

/// Scrolling, for messages longer than one revolution. Preview-only, like the geometry.
enum Motion {
    /// Marquee speed. One glyph is six columns, so this is five characters per second.
    static let scrollColumnsPerSecond: Double = 30
    /// Dark columns appended before the message wraps, so its end never touches its start.
    static let scrollGapColumns = 18
    /// Redraw cadence while scrolling; 30 Hz is smooth for 3 px dots and cheap.
    static let frameInterval: TimeInterval = 1.0 / 30.0
}
