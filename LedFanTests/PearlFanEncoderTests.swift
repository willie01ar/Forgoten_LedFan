import Foundation
import Testing
@testable import LedFan

struct PearlFanEncoderTests {
    private func message(_ text: String, slot: Int = 0) throws -> FanMessage { try FanMessage(slot: slot, text: text) }

    // MARK: - Header

    @Test func theDefaultHeaderIsTheReferenceConstant() {
        #expect(PearlFanEffects.remain.header(imageID: 0) == [0xA0, 0x10, 0x00, 0x00, 0x55, 0x00, 0x00, 0x00])
    }

    @Test func theHeaderPacksCloseOpenIDAndMotion() {
        let effects = PearlFanEffects(open: .leftToRight, close: .symmetric, beforeClose: .anticlockwise)
        // options = close 2 | open 1<<4 | id 3<<8 | before 6<<12 = 0x6312, little-endian at bytes 2-3
        #expect(effects.header(imageID: 3) == [0xA0, 0x10, 0x12, 0x63, 0x55, 0x00, 0x00, 0x00])
    }

    @Test func theImageIDComesFromTheSlot() throws {
        let reports = try PearlFanEncoder().reports(for: [message("HI", slot: 7)])
        #expect(reports[0][3] == 0x07)
    }

    @Test func fastModeIsRefusedForClosing() {
        #expect(PearlFanEffects(close: .fastMode).close == .rightToLeft)
        #expect(PearlFanEffects(open: .fastMode).open == .fastMode)
    }

    @Test func remainIsTheDefaultMotion() {
        #expect(PearlFanEffects().beforeClose == .remain)
        #expect(PearlFanEffects.Motion.remain.rawValue == 0)
    }

    // MARK: - Data reports

    @Test func everyMessageIsExactlyFortyReportsOfEightBytes() throws {
        let reports = try PearlFanEncoder().reports(for: [message("A"), message("", slot: 1)])
        #expect(reports.count == 2 * PearlFanEncoder.reportsPerImage)
        #expect(reports.allSatisfy { $0.count == 8 })
        #expect(reports[40] == PearlFanEffects.remain.header(imageID: 1))
    }

    @Test func aLitPixelClearsItsBitAndColumnsAreReversedOnTheWire() throws {
        // One glyph column with rows 3...8 lit, at disc column 0, so it is the LAST word sent.
        let encoder = PearlFanEncoder(rasterizer: StubRasterizer(columnsPerCharacter: [0b111_1110 << 2]))
        let reports = try encoder.reports(for: [message("X")])
        let last = reports[39]
        #expect(last[6...7] == [0xFE, 0x07])          // 0xFFFF & ~(0x0001|0x8000|0x4000|0x2000|0x1000|0x0800)
        #expect(last[0...5] == [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        #expect(reports[1] == [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    @Test func aMessageWiderThanTheDiscIsRefusedNotCut() {
        let encoder = PearlFanEncoder(rasterizer: StubRasterizer(columnsPerCharacter: Array(repeating: 0, count: 157)))
        #expect(throws: FanTransportError.imageTooWide(columns: 157, limit: 156)) {
            try encoder.reports(for: [try FanMessage(slot: 0, text: "X")])
        }
    }

    @Test func twentySixCharactersFillTheDiscExactly() throws {
        let strip = ColumnRasterizer().strip(for: "THE QUICK BROWN FOX JUMPS!", ledsPerArm: 11)
        #expect(strip.columns.count == PearlFanEncoder.columnsPerImage)
    }

    @Test func encodingIsPure() throws {
        let messages = [try message("HELLO"), try message("WORLD", slot: 1)]
        #expect(try PearlFanEncoder().reports(for: messages) == (try PearlFanEncoder().reports(for: messages)))
    }
}
