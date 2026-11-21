import Foundation

/// sRGB color value with WCAG contrast math. Pure Foundation so it is unit-testable anywhere.
public struct RGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// `0xRRGGBB`
    public init(hex: UInt32) {
        self.init(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255
        )
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio, 1...21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `self` composited over `background` at `alpha` (for tinted chip backgrounds).
    public func blended(over background: RGB, alpha: Double) -> RGB {
        RGB(
            r: r * alpha + background.r * (1 - alpha),
            g: g * alpha + background.g * (1 - alpha),
            b: b * alpha + background.b * (1 - alpha)
        )
    }
}

/// Score level names — thresholds from docs/03-ML-MODEL.md:
/// 0–20 Beginner · 20–40 Developing · 40–60 Intermediate · 60–80 Advanced · 80–95 Expert · 95+ Elite.
public enum ScoreLevel: Int, CaseIterable, Sendable {
    case beginner, developing, intermediate, advanced, expert, elite

    public init(score: Double) {
        let s = score.isFinite ? score : 0
        switch s {
        case ..<20: self = .beginner
        case ..<40: self = .developing
        case ..<60: self = .intermediate
        case ..<80: self = .advanced
        case ..<95: self = .expert
        default: self = .elite
        }
    }

    /// String Catalog key (table: Localizable, bundle: DesignSystem).
    public var localizationKey: String {
        switch self {
        case .beginner: "ds.scoreLevel.beginner"
        case .developing: "ds.scoreLevel.developing"
        case .intermediate: "ds.scoreLevel.intermediate"
        case .advanced: "ds.scoreLevel.advanced"
        case .expert: "ds.scoreLevel.expert"
        case .elite: "ds.scoreLevel.elite"
        }
    }
}

/// Complete color set for one appearance. Single source of truth; `DSColor` wraps these
/// into dynamic SwiftUI colors and tests assert WCAG AA on them.
public struct Palette: Sendable {
    // Backgrounds (low → high elevation)
    public let background: RGB
    public let surface: RGB
    public let surfaceRaised: RGB
    public let surfaceOverlay: RGB
    public let separator: RGB
    // Text
    public let textPrimary: RGB
    public let textSecondary: RGB
    public let textTertiary: RGB
    // Brand blue. `accent` is the foreground-safe tone (text, icons, strokes: AA on every surface);
    // `accentFill` is the exact brand blue for fills (buttons, bars, selected chips) with `onAccent` on top.
    public let accent: RGB
    public let accentFill: RGB
    public let onAccent: RGB
    // Brand orange, same split: `highlight` for foreground, `highlightFill` for fills with `onHighlight` on top.
    public let highlight: RGB
    public let highlightFill: RGB
    public let onHighlight: RGB
    // Status
    public let success: RGB
    public let warning: RGB
    public let error: RGB
    // Score scale, indexed by `ScoreLevel.rawValue`
    public let levels: [RGB]

    public func level(_ level: ScoreLevel) -> RGB { levels[level.rawValue] }

    /// Brand palette: pure black base, #105BFF blue, #FE8500 orange. Surfaces are lighter steps of the base.
    public static let dark = Palette(
        background: RGB(hex: 0x000000),
        surface: RGB(hex: 0x2A2D3A),
        surfaceRaised: RGB(hex: 0x343847),
        surfaceOverlay: RGB(hex: 0x3E4354),
        separator: RGB(hex: 0x4B5164),
        textPrimary: RGB(hex: 0xF4F5F9),
        textSecondary: RGB(hex: 0xB6BBC8),
        textTertiary: RGB(hex: 0xA0A6B5),
        accent: RGB(hex: 0x74A0FF), // #105BFF lightened until it holds AA on every dark surface
        accentFill: RGB(hex: 0x105BFF),
        onAccent: RGB(hex: 0xFFFFFF),
        highlight: RGB(hex: 0xFE8500),
        highlightFill: RGB(hex: 0xFE8500),
        onHighlight: RGB(hex: 0x21232E),
        success: RGB(hex: 0x3DDC97),
        warning: RGB(hex: 0xFFC53D),
        error: RGB(hex: 0xFF7777),
        levels: [
            RGB(hex: 0x9AA3B2), // beginner  – steel
            RGB(hex: 0x4CC2FF), // developing – sky
            RGB(hex: 0x2EE6C5), // intermediate – teal
            RGB(hex: 0xFFC53D), // advanced – amber
            RGB(hex: 0xFF8A3D), // expert – orange
            RGB(hex: 0xC48BFF)  // elite – violet
        ]
    )

    /// Same hues, darkened so they hold AA on white/light-gray surfaces.
    public static let light = Palette(
        background: RGB(hex: 0xF2F4F7),
        surface: RGB(hex: 0xFFFFFF),
        surfaceRaised: RGB(hex: 0xEDEFF3),
        surfaceOverlay: RGB(hex: 0xE1E5EB),
        separator: RGB(hex: 0xD3D8E0),
        textPrimary: RGB(hex: 0x21232E),
        textSecondary: RGB(hex: 0x474F5B),
        textTertiary: RGB(hex: 0x515A68),
        accent: RGB(hex: 0x0E51E3), // #105BFF nudged darker so tinted chips hold AA
        accentFill: RGB(hex: 0x105BFF),
        onAccent: RGB(hex: 0xFFFFFF),
        highlight: RGB(hex: 0x934D00), // #FE8500 darkened for AA text on light surfaces
        highlightFill: RGB(hex: 0xFE8500),
        onHighlight: RGB(hex: 0x21232E),
        success: RGB(hex: 0x076B41),
        warning: RGB(hex: 0x7A4F00),
        error: RGB(hex: 0xB32323),
        levels: [
            RGB(hex: 0x515A68),
            RGB(hex: 0x095F91),
            RGB(hex: 0x076B59),
            RGB(hex: 0x7A4F00),
            RGB(hex: 0x9C4100),
            RGB(hex: 0x7336BB)
        ]
    )
}
