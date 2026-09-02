import Testing
@testable import LedFan

struct FrameComposerTests {
    private let composer = RevolutionComposer()
    private let geometry = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)
    private let rasterizer = ColumnRasterizer()

    // MARK: - Invariants

    @Test func aFrameAlwaysHasExactlyOneRevolutionOfColumns() {
        let short = composer.frame(from: rasterizer.strip(for: "HI", ledsPerArm: 11), geometry: geometry, columnOffset: 0)
        let long = composer.frame(from: rasterizer.strip(for: String(repeating: "W", count: 60), ledsPerArm: 11), geometry: geometry, columnOffset: 0)
        let empty = composer.frame(from: .empty(ledsPerArm: 11), geometry: geometry, columnOffset: 0)
        #expect(short.columns.count == 180)
        #expect(long.columns.count == 180)
        #expect(empty.columns.count == 180)
        #expect(empty.isBlank)
    }

    @Test func aZeroColumnGeometryYieldsABlankFrameNotACrash() {
        let frame = composer.frame(from: rasterizer.strip(for: "HI", ledsPerArm: 11), geometry: FanGeometry(ledsPerArm: 11, columnsPerRevolution: 0), columnOffset: 5)
        #expect(frame.columns.isEmpty)
    }

    // MARK: - Placement

    @Test func aShortStripOccupiesAProportionalArcAndTheRestIsDark() {
        let strip = rasterizer.strip(for: "HELLO", ledsPerArm: 11)
        let frame = composer.frame(from: strip, geometry: geometry, columnOffset: 0)

        let litStripColumns = strip.columns.count { $0 != 0 }
        #expect(frame.litColumnCount == litStripColumns)
        #expect(frame.columns[strip.columns.count...].allSatisfy { $0 == 0 })
    }

    @Test func columnOffsetShiftsTheStripAroundTheDisc() {
        let strip = rasterizer.strip(for: "HELLO", ledsPerArm: 11)
        let base = composer.frame(from: strip, geometry: geometry, columnOffset: 0)
        let shifted = composer.frame(from: strip, geometry: geometry, columnOffset: 40)

        for column in 0..<180 {
            #expect(shifted.columns[(column + 40) % 180] == base.columns[column])
        }
        #expect(shifted != base)
    }

    @Test func negativeOffsetsWrapBackwards() {
        let strip = rasterizer.strip(for: "HELLO", ledsPerArm: 11)
        let base = composer.frame(from: strip, geometry: geometry, columnOffset: 0)
        let shifted = composer.frame(from: strip, geometry: geometry, columnOffset: -15)

        for column in 0..<180 {
            #expect(shifted.columns[(column + 165) % 180] == base.columns[column])
        }
    }

    @Test func aFullRevolutionOffsetIsTheIdentity() {
        let strip = rasterizer.strip(for: "HELLO", ledsPerArm: 11)
        #expect(composer.frame(from: strip, geometry: geometry, columnOffset: 180)
                == composer.frame(from: strip, geometry: geometry, columnOffset: 0))
    }

    @Test func aStripLongerThanARevolutionShowsAWindowAndWraps() {
        let strip = ColumnStrip(ledsPerArm: 11, columns: (0..<250).map { UInt16($0 % 7 + 1) })
        let start = composer.frame(from: strip, geometry: geometry, columnOffset: 0)
        let scrolled = composer.frame(from: strip, geometry: geometry, columnOffset: -100)

        // Offset 0 shows strip columns 0..<180; offset -100 shows 100..<250 then wraps to 0..<30.
        #expect(start.columns[0] == RevolutionComposer.mirrorForTests(strip.columns[0], ledsPerArm: 11))
        #expect(scrolled.columns[0] == RevolutionComposer.mirrorForTests(strip.columns[100], ledsPerArm: 11))
        #expect(scrolled.columns[150] == RevolutionComposer.mirrorForTests(strip.columns[0], ledsPerArm: 11))
    }

    // MARK: - Orientation

    @Test func glyphTopsLandOnTheOuterLED() {
        // Strip bit 0 is the glyph's top row; on the disc it must be the outermost LED.
        let strip = ColumnStrip(ledsPerArm: 11, columns: [0b0000_0000_001])
        let frame = composer.frame(from: strip, geometry: geometry, columnOffset: 0)
        #expect(frame.columns[0] == 1 << 10)
    }

    @Test func mirroringIsMaskedToTheArm() {
        let strip = ColumnStrip(ledsPerArm: 11, columns: [0xFFFF])
        let frame = composer.frame(from: strip, geometry: geometry, columnOffset: 0)
        #expect(frame.columns[0] == 0x07FF)
    }
}

private extension RevolutionComposer {
    static func mirrorForTests(_ column: UInt16, ledsPerArm: Int) -> UInt16 {
        RevolutionComposer().frame(from: ColumnStrip(ledsPerArm: ledsPerArm, columns: [column]),
                                   geometry: FanGeometry(ledsPerArm: ledsPerArm, columnsPerRevolution: 1),
                                   columnOffset: 0).columns[0]
    }
}
