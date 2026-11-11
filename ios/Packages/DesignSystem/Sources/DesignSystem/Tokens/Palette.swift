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
        case .beginner: "score.level.beginner"
        case .developing: "score.level.developing"
        case .intermediate: "score.level.intermediate"
        case .advanced: "score.level.advanced"
        case .expert: "score.level.expert"
        case .elite: "score.level.elite"
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
    // The one vivid accent
    public let accent: RGB
    public let onAccent: RGB
    // Status
    public let success: RGB
    public let warning: RGB
    public let error: RGB
    // Score scale, indexed by `ScoreLevel.rawValue`
    public let levels: [RGB]

    public func level(_ level: ScoreLevel) -> RGB { levels[level.rawValue] }

    /// Electric lime accent on near-black.
    public static let dark = Palette(
        background: RGB(hex: 0x0A0C0F),
        surface: RGB(hex: 0x13161B),
        surfaceRaised: RGB(hex: 0x1B1F26),
        surfaceOverlay: RGB(hex: 0x252A33),
        separator: RGB(hex: 0x2E343F),
        textPrimary: RGB(hex: 0xF3F5F8),
        textSecondary: RGB(hex: 0xA9B1BD),
        textTertiary: RGB(hex: 0x8B94A2),
        accent: RGB(hex: 0xC6F135),
        onAccent: RGB(hex: 0x0A0C0F),
        success: RGB(hex: 0x3DDC97),
        warning: RGB(hex: 0xFFC53D),
        error: RGB(hex: 0xFF6B6B),
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
        textPrimary: RGB(hex: 0x0E1116),
        textSecondary: RGB(hex: 0x474F5B),
        textTertiary: RGB(hex: 0x515A68),
        accent: RGB(hex: 0x4A6A00),
        onAccent: RGB(hex: 0xFFFFFF),
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
