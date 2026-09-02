import Testing
@testable import LedFan

struct MessageRasterizerTests {
    private let rasterizer = ColumnRasterizer(letterSpacing: 1)

    @Test func emptyTextProducesNoColumns() {
        let strip = rasterizer.strip(for: "", ledsPerArm: 11)
        #expect(strip.columns.isEmpty)
        #expect(strip.isEmpty)
    }

    @Test func zeroLEDsProducesNoColumns() {
        #expect(rasterizer.strip(for: "A", ledsPerArm: 0).columns.isEmpty)
    }

    @Test func negativeLEDCountIsClampedToZero() {
        let strip = rasterizer.strip(for: "A", ledsPerArm: -3)
        #expect(strip.columns.isEmpty)
        #expect(strip.ledsPerArm == 0)
    }

    @Test func oneGlyphProducesGlyphWidthPlusSpacing() {
        let strip = rasterizer.strip(for: "A", ledsPerArm: 11)
        #expect(strip.columns.count == GlyphFont.glyphWidth + 1)
    }

    @Test func letterSpacingIsConfigurable() {
        #expect(ColumnRasterizer(letterSpacing: 0).strip(for: "A", ledsPerArm: 11).columns.count == GlyphFont.glyphWidth)
        #expect(ColumnRasterizer(letterSpacing: 3).strip(for: "A", ledsPerArm: 11).columns.count == GlyphFont.glyphWidth + 3)
        #expect(ColumnRasterizer(letterSpacing: -2).letterSpacing == 0)
    }

    @Test func glyphIsCentredVertically() {
        // 11 LEDs, 7-row glyph, so the glyph starts two LEDs up.
        let strip = rasterizer.strip(for: "A", ledsPerArm: 11)
        #expect(strip.columns.first == UInt16(0x7E) << 2)
    }

    @Test func glyphIsNotShiftedWhenTheArmIsShorterThanTheGlyph() {
        let strip = rasterizer.strip(for: "A", ledsPerArm: 5)
        #expect(strip.columns.first == UInt16(0x7E) & 0x1F)
    }

    @Test func columnsAreMaskedToTheArmLength() {
        let strip = rasterizer.strip(for: "A", ledsPerArm: 7)
        for column in strip.columns {
            #expect(column <= 0x7F)
        }
    }

    @Test func armsOfSixteenOrMoreLEDsAreNotMasked() {
        let strip = rasterizer.strip(for: "A", ledsPerArm: 16)
        #expect(strip.columns.first == UInt16(0x7E) << 4)
    }

    @Test func lowercaseMatchesUppercase() {
        let lower = rasterizer.strip(for: "a", ledsPerArm: 11)
        let upper = rasterizer.strip(for: "A", ledsPerArm: 11)
        #expect(lower == upper)
    }

    @Test(arguments: ["\u{1F600}", "\u{07}", "\u{00}", "ß", "é"])
    func unsupportedCharacterFallsBackToBlank(text: String) {
        let strip = rasterizer.strip(for: text, ledsPerArm: 11)
        #expect(strip.columns.count == GlyphFont.glyphWidth + 1)
        #expect(strip.columns.allSatisfy { $0 == 0 })
        #expect(text.allSatisfy { !GlyphFont.supports($0) })
    }

    @Test func multipleGlyphsAccumulate() {
        let strip = rasterizer.strip(for: "AB", ledsPerArm: 11)
        #expect(strip.columns.count == 2 * (GlyphFont.glyphWidth + 1))
    }

    @Test func aTwentySixCharacterMessageIsLongerThanNothingButShorterThanARevolution() {
        let strip = rasterizer.strip(for: "THE QUICK BROWN FOX JUMPS!", ledsPerArm: 11)
        #expect(strip.columns.count == 26 * (GlyphFont.glyphWidth + 1))
        #expect(strip.columns.count < FanGeometry.preview.columnsPerRevolution)
    }

    @Test func rasterizationIsDeterministic() {
        let first = rasterizer.strip(for: "Hello, fan! 123", ledsPerArm: 11)
        let second = rasterizer.strip(for: "Hello, fan! 123", ledsPerArm: 11)
        #expect(first == second)
    }
}
