import Foundation

/// In-app language choice. `.system` follows iOS; otherwise the app forces that locale.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, turkish = "tr", english = "en"

    var id: String { rawValue }

    /// nil for `.system` (no override).
    var locale: Locale? {
        switch self {
        case .system: nil
        case .turkish: Locale(identifier: "tr")
        case .english: Locale(identifier: "en")
        }
    }

    /// Native names are shown untranslated so users can always find their own language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }
}
