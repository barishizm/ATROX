import Foundation
import Testing
@testable import DesignSystem

@Suite struct PaletteTests {
    static let palettes: [(String, Palette)] = [("dark", .dark), ("light", .light)]

    @Test func contrastMath() {
        let white = RGB(hex: 0xFFFFFF), black = RGB(hex: 0x000000)
        #expect(abs(RGB.contrast(white, black) - 21) < 1e-9)
        #expect(abs(RGB.contrast(white, white) - 1) < 1e-9)
        // Known reference: #767676 on white is ~4.54:1
        #expect(abs(RGB.contrast(RGB(hex: 0x767676), white) - 4.54) < 0.01)
    }

    @Test(arguments: palettes) func textMeetsAAOnEverySurface(name: String, p: Palette) {
        for surface in [p.background, p.surface, p.surfaceRaised] {
            for text in [p.textPrimary, p.textSecondary, p.textTertiary] {
                #expect(RGB.contrast(text, surface) >= 4.5, "\(name) text \(text) on \(surface)")
            }
        }
    }

    @Test(arguments: palettes) func accentAndOnAccentMeetAA(name: String, p: Palette) {
        #expect(RGB.contrast(p.onAccent, p.accentFill) >= 4.5, "\(name) onAccent/accentFill")
        for surface in [p.background, p.surface, p.surfaceRaised] {
            #expect(RGB.contrast(p.accent, surface) >= 4.5, "\(name) accent on \(surface)")
        }
    }

    @Test(arguments: palettes) func highlightAndOnHighlightMeetAA(name: String, p: Palette) {
        #expect(RGB.contrast(p.onHighlight, p.highlightFill) >= 4.5, "\(name) onHighlight/highlightFill")
        for surface in [p.background, p.surface, p.surfaceRaised] {
            #expect(RGB.contrast(p.highlight, surface) >= 4.5, "\(name) highlight on \(surface)")
        }
    }

    /// The three brand colors are exact: #21232E base, #105BFF blue fill, #FE8500 orange fill.
    @Test func brandColorsAreExact() {
        #expect(Palette.dark.background == RGB(hex: 0x21232E))
        #expect(Palette.light.textPrimary == RGB(hex: 0x21232E))
        for p in [Palette.dark, Palette.light] {
            #expect(p.accentFill == RGB(hex: 0x105BFF))
            #expect(p.highlightFill == RGB(hex: 0xFE8500))
        }
    }

    @Test(arguments: palettes) func statusAndLevelColorsReadableAsTextOnSurface(name: String, p: Palette) {
        for c in [p.success, p.warning, p.error] + p.levels {
            #expect(RGB.contrast(c, p.surface) >= 4.5, "\(name) \(c) on surface")
        }
    }

    @Test(arguments: palettes) func tintedChipsMeetAA(name: String, p: Palette) {
        let tints = [p.accent, p.highlight, p.success, p.warning, p.error, p.textSecondary] + p.levels
        for tint in tints {
            let chipBackground = tint.blended(over: p.background, alpha: TagChip.tintOpacity)
            #expect(RGB.contrast(tint, chipBackground) >= 4.5, "\(name) chip \(tint)")
        }
    }

    @Test(arguments: palettes) func levelColorsAreDistinctAndComplete(name: String, p: Palette) {
        #expect(p.levels.count == ScoreLevel.allCases.count)
        #expect(Set(p.levels.map { "\($0.r),\($0.g),\($0.b)" }).count == p.levels.count)
    }

    @Test(arguments: palettes) func surfacesAreLayeredByElevation(name: String, p: Palette) {
        // Dark: higher layers lighter. Light: surface (white) is the top, background the base.
        let l = [p.background, p.surface, p.surfaceRaised, p.surfaceOverlay].map(\.relativeLuminance)
        if name == "dark" {
            #expect(l == l.sorted())
        } else {
            #expect(l[1] > l[0] && l[2] < l[1] && l[3] < l[2])
        }
    }
}
