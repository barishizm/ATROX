import Foundation

/// The 17 catalog muscles (docs/00-KARARLAR.md §5.4). Raw values equal the snake_case strings stored in
/// `exercises.primary_muscles` / `secondary_muscles`, so `Muscle(rawValue:)` converts catalog data directly.
public enum Muscle: String, CaseIterable, Sendable, Hashable, Codable {
    case abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats
    case lowerBack = "lower_back"
    case middleBack = "middle_back"
    case neck, quadriceps, shoulders, traps, triceps

    var localizationKey: String { "muscle.\(rawValue)" }

    /// Localized muscle name in the device language (String Catalog table `Muscles`).
    public var localizedName: String {
        NSLocalizedString(localizationKey, tableName: "Muscles", bundle: .module, comment: "Muscle name")
    }

    /// Same, for an explicit locale (the in-app language override does not change the process language).
    public func localizedName(locale: Locale) -> String {
        Self.localized(localizationKey, locale: locale) ?? localizedName
    }

    static func localized(_ key: String, locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier,
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        return bundle.localizedString(forKey: key, value: nil, table: "Muscles")
    }
}
