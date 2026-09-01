import Testing
@testable import LedFan

struct MessageRasterizerTests {
    private let rasterizer = ColumnRasterizer(letterSpacing: 1)

    @Test func emptyTextProducesNoColumns() {
        let frame = rasterizer.frame(for: "", ledsPerArm: 11)
        #expect(frame.columns.isEmpty)
        #expect(frame.isEmpty)
    }

    @Test func zeroLEDsProducesNoColumns() {
        #expect(rasterizer.frame(for: "A", ledsPerArm: 0).columns.isEmpty)
    }

    @Test func negativeLEDCountIsClampedToZero() {
        let frame = rasterizer.frame(for: "A", ledsPerArm: -3)
        #expect(frame.columns.isEmpty)
        #expect(frame.ledsPerArm == 0)
    }

    @Test func oneGlyphProducesGlyphWidthPlusSpacing() {
        let frame = rasterizer.frame(for: "A", ledsPerArm: 11)
        #expect(frame.columns.count == GlyphFont.glyphWidth + 1)
    }

    @Test func letterSpacingIsConfigurable() {
        #expect(ColumnRasterizer(letterSpacing: 0).frame(for: "A", ledsPerArm: 11).columns.count == GlyphFont.glyphWidth)
        #expect(ColumnRasterizer(letterSpacing: 3).frame(for: "A", ledsPerArm: 11).columns.count == GlyphFont.glyphWidth + 3)
        #expect(ColumnRasterizer(letterSpacing: -2).letterSpacing == 0)
    }

    @Test func glyphIsCentredVertically() {
        // 11 LEDs, 7-row glyph, so the glyph starts two LEDs up.
        let frame = rasterizer.frame(for: "A", ledsPerArm: 11)
        #expect(frame.columns.first == UInt16(0x7E) << 2)
    }

    @Test func glyphIsNotShiftedWhenTheArmIsShorterThanTheGlyph() {
        let frame = rasterizer.frame(for: "A", ledsPerArm: 5)
        #expect(frame.columns.first == UInt16(0x7E) & 0x1F)
    }

    @Test func columnsAreMaskedToTheArmLength() {
        let frame = rasterizer.frame(for: "A", ledsPerArm: 7)
        for column in frame.columns {
            #expect(column <= 0x7F)
        }
    }

    @Test func armsOfSixteenOrMoreLEDsAreNotMasked() {
        let frame = rasterizer.frame(for: "A", ledsPerArm: 16)
        #expect(frame.columns.first == UInt16(0x7E) << 4)
    }

    @Test func lowercaseMatchesUppercase() {
        let lower = rasterizer.frame(for: "a", ledsPerArm: 11)
        let upper = rasterizer.frame(for: "A", ledsPerArm: 11)
        #expect(lower == upper)
    }

    @Test(arguments: ["\u{1F600}", "\u{07}", "\u{00}", "ß", "é"])
    func unsupportedCharacterFallsBackToBlank(text: String) {
        let frame = rasterizer.frame(for: text, ledsPerArm: 11)
        #expect(frame.columns.count == GlyphFont.glyphWidth + 1)
        #expect(frame.columns.allSatisfy { $0 == 0 })
    }

    @Test func multipleGlyphsAccumulate() {
        let frame = rasterizer.frame(for: "AB", ledsPerArm: 11)
        #expect(frame.columns.count == 2 * (GlyphFont.glyphWidth + 1))
    }

    @Test func rasterizationIsDeterministic() {
        let first = rasterizer.frame(for: "Hello, fan! 123", ledsPerArm: 11)
        let second = rasterizer.frame(for: "Hello, fan! 123", ledsPerArm: 11)
        #expect(first == second)
    }
}
