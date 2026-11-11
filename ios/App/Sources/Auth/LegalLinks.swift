import Foundation

/// Terms of Use / Privacy Policy URLs, read from Info.plist (`LegalTermsURL`, `LegalPrivacyURL`),
/// which come from `LEGAL_TERMS_URL` / `LEGAL_PRIVACY_URL` in the xcconfig files.
struct LegalLinks: Equatable, Sendable {
    let terms: URL?
    let privacy: URL?

    init(terms: URL?, privacy: URL?) {
        self.terms = terms
        self.privacy = privacy
    }

    init(infoDictionary: [String: Any]) {
        self.init(
            terms: Self.url(infoDictionary["LegalTermsURL"]),
            privacy: Self.url(infoDictionary["LegalPrivacyURL"])
        )
    }

    static var current: LegalLinks { LegalLinks(infoDictionary: Bundle.main.infoDictionary ?? [:]) }

    /// Only web links; an empty value or an unexpanded `$(VAR)` means "not configured".
    private static func url(_ value: Any?) -> URL? {
        guard
            let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty, !string.hasPrefix("$("),
            let url = URL(string: string), url.scheme == "https" || url.scheme == "http", url.host != nil
        else { return nil }
        return url
    }
}
