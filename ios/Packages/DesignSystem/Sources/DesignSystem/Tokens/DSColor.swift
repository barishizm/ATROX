import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Dynamic color resolving to `light` or `dark` with the current appearance.
    init(light: RGB, dark: RGB) {
        #if canImport(UIKit)
        self = Color(uiColor: UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.r, green: v.g, blue: v.b, alpha: 1)
        })
        #else
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: v.r, green: v.g, blue: v.b, alpha: 1)
        })
        #endif
    }
}

/// Semantic color tokens (adapt to light/dark automatically). Never use raw hex in features.
public enum DSColor {
    private static func pair(_ keyPath: KeyPath<Palette, RGB>) -> Color {
        Color(light: Palette.light[keyPath: keyPath], dark: Palette.dark[keyPath: keyPath])
    }

    // Backgrounds
    public static let background = pair(\.background)
    public static let surface = pair(\.surface)
    public static let surfaceRaised = pair(\.surfaceRaised)
    public static let surfaceOverlay = pair(\.surfaceOverlay)
    public static let separator = pair(\.separator)
    // Text
    public static let textPrimary = pair(\.textPrimary)
    public static let textSecondary = pair(\.textSecondary)
    public static let textTertiary = pair(\.textTertiary)
    // Accent
    public static let accent = pair(\.accent)
    public static let onAccent = pair(\.onAccent)
    // Status
    public static let success = pair(\.success)
    public static let warning = pair(\.warning)
    public static let error = pair(\.error)

    /// Color for a score level (Beginner → Elite).
    public static func level(_ level: ScoreLevel) -> Color {
        Color(light: Palette.light.level(level), dark: Palette.dark.level(level))
    }
}

/// App-level appearance preference. Dark is the product default (docs/00-KARARLAR.md #16).
public enum AppearancePreference: String, CaseIterable, Sendable {
    case dark, light, system

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

extension View {
    /// Apply once at the app root: sets the appearance (dark by default) and background.
    public func dsRootTheme(_ preference: AppearancePreference = .dark) -> some View {
        self
            .preferredColorScheme(preference.colorScheme)
            .tint(DSColor.accent)
            .background(DSColor.background.ignoresSafeArea())
    }
}
