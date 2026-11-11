import DataKit
import DesignSystem
import Foundation
import Observation

/// Persisted theme choice (system / dark / light). Dark stays the product default (docs/00-KARARLAR.md #16).
/// The value lives in `UserDefaults` so the first frame is themed before the SwiftData settings are read;
/// `ProfileModel` writes the same choice to `UserSettings` so it syncs with the account.
@MainActor
@Observable
final class AppearanceSettings {
    static let storageKey = "settings.theme"

    var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: Self.storageKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: Self.storageKey).flatMap(ThemePreference.init(rawValue:)) ?? .dark
    }

    var preference: AppearancePreference {
        switch theme {
        case .system: .system
        case .dark: .dark
        case .light: .light
        }
    }
}
