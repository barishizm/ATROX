import Foundation
import Observation

/// Persisted in-app language selection (system / TR / EN). Inject via `AppContainer`; apply with `.environment(\.locale, …)`.
@MainActor
@Observable
final class LanguageSettings {
    static let storageKey = "settings.language"

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.storageKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var localeOverride: Locale? { language.locale }

    func effectiveLocale(system: Locale = .autoupdatingCurrent) -> Locale {
        localeOverride ?? system
    }
}
