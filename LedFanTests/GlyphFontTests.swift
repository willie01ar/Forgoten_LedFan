import Foundation
import Testing
@testable import LedFan

struct GlyphFontTests {
    @Test func everyLowercaseLetterHasItsOwnGlyph() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            #expect(GlyphFont.supports(letter))
            #expect(GlyphFont.columns(for: letter) != GlyphFont.columns(for: Character(letter.uppercased())), "\(letter) must not fall back to its capital")
            #expect(GlyphFont.columns(for: letter).count == GlyphFont.glyphWidth)
        }
    }

    @Test func lowercaseSitsOnTheBaselineAndDescendersGoBelowIt() {
        let baselineRow = GlyphFont.glyphHeight - 1
        for letter in "acemnorsuvwxz" {
            let rows = usedRows(letter)
            #expect(rows.max() == baselineRow, "\(letter) ends on the baseline")
            #expect(rows.min()! >= 2, "\(letter) is x-height")
        }
        for letter in "gjpqy" {
            #expect(usedRows(letter).max() == GlyphFont.descenderRow, "\(letter) has a descender")
        }
        for letter in "bdfhklt" {
            #expect(usedRows(letter).min()! <= 1, "\(letter) has an ascender")
        }
    }

    @Test func aDescenderRendersBelowItsNeighboursNotClippedOrShifted() {
        // 11 LEDs, glyph top at row 2: the baseline lands at row 8 and a descender at row 9.
        let strip = ColumnRasterizer().strip(for: "ag", ledsPerArm: 11)
        let aColumns = Array(strip.columns[0..<5]), gColumns = Array(strip.columns[6..<11])
        #expect(aColumns.allSatisfy { $0 >> 9 == 0 }, "a stays above row 9")
        #expect(aColumns.contains { $0 & (1 << 8) != 0 }, "a touches the baseline at row 8")
        #expect(gColumns.contains { $0 & (1 << 9) != 0 }, "g reaches row 9, below the baseline")
        #expect(gColumns.allSatisfy { $0 >> 10 == 0 }, "nothing is pushed past the last LED")
        #expect(gColumns.contains { $0 & (1 << 8) != 0 }, "g still shares the baseline; it was not shifted up")
    }

    @Test func charactersWithoutAGlyphStillFallBackToTheirCapital() {
        #expect(GlyphFont.columns(for: "é") == GlyphFont.blankGlyph)
        #expect(GlyphFont.columns(for: "ß") == GlyphFont.blankGlyph)
        #expect(!GlyphFont.supports("é"))
    }

    @Test func theFactoryDemoLineRendersEveryCharacter() {
        for character in "*Mom Pick me up @4P*" where character != " " {
            #expect(GlyphFont.supports(character), "\(character)")
        }
    }

    private func usedRows(_ letter: Character) -> [Int] {
        GlyphFont.columns(for: letter).flatMap { column in (0..<8).filter { column & (1 << $0) != 0 } }
    }
}
