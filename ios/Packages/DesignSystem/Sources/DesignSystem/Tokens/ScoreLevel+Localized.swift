import Foundation

extension ScoreLevel {
    /// Localized level name (Beginner … Elite) from the DesignSystem string catalog, in the device language.
    public var localizedName: String {
        NSLocalizedString(localizationKey, bundle: .module, comment: "Score level name")
    }

    /// Same, for an explicit locale (the app's in-app language override does not change the process language).
    public func localizedName(locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier,
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return localizedName }
        return bundle.localizedString(forKey: localizationKey, value: nil, table: nil)
    }
}
