import Foundation

extension ScoreLevel {
    /// Localized level name (Başlangıç … Elit) from the DesignSystem string catalog.
    public var localizedName: String {
        NSLocalizedString(localizationKey, bundle: .module, comment: "Score level name")
    }
}
