import Foundation

/// Username and display-name rules (P086). Mirrors `social_username_ok` / `social_text_ok` in the P085 migration so the
/// form can answer instantly; the server stays the authority.
public enum SocialTextPolicy {
    public static let usernameLength = 3...20
    public static let displayNameLength = 1...30

    static let reserved: Set<String> = [
        "admin", "administrator", "atrox", "support", "help", "moderator", "mod", "staff", "team", "official",
        "system", "root", "null", "undefined", "anonymous", "coach", "ai", "apple", "google", "security", "billing"
    ]
    /// Matched as substrings of the normalised text.
    static let blockedSubstrings = [
        "fuck", "shit", "bitch", "cunt", "nigg", "faggot", "whore", "rapist", "nazi", "hitler",
        "orospu", "sikik", "siktir", "yarrak", "amcik", "pezevenk", "ibne", "gavat"
    ]
    /// Short words that are only blocked when they are the whole text.
    static let blockedWholeWords: Set<String> = ["amk", "aq", "got"]

    public enum UsernameIssue: Equatable, Sendable {
        case tooShort, tooLong, invalidCharacters, reserved, inappropriate
    }

    /// Lowercase, trimmed; what is sent to the server.
    public static func canonical(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func usernameIssue(_ raw: String) -> UsernameIssue? {
        let name = canonical(raw)
        if name.count < usernameLength.lowerBound { return .tooShort }
        if name.count > usernameLength.upperBound { return .tooLong }
        guard name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return .invalidCharacters }
        if reserved.contains(name) { return .reserved }
        if !isTextAllowed(name) { return .inappropriate }
        return nil
    }

    public static func isDisplayNameValid(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayNameLength.contains(name.count) && isTextAllowed(name)
    }

    public static func isTextAllowed(_ text: String) -> Bool {
        let normal = normalize(text)
        if blockedWholeWords.contains(normal) { return false }
        return !blockedSubstrings.contains { normal.contains($0) }
    }

    /// Lowercase, fold leetspeak and Turkish letters, drop everything that is not a letter or digit.
    static func normalize(_ text: String) -> String {
        let map: [Unicode.Scalar: Unicode.Scalar] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s",
            "ı": "i", "ğ": "g", "ü": "u", "ş": "s", "ö": "o", "ç": "c"
        ]
        // Scalars, not Characters: `İ`.lowercased() is "i" + a combining dot, one Character; the dot is dropped below.
        var out = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            let folded = map[scalar] ?? scalar
            if folded.isASCII, folded.properties.isAlphabetic || ("0"..."9").contains(folded) { out.append(folded) }
        }
        return String(out)
    }
}
