import Foundation

/// Client-side checks that mirror the server policy (`supabase/config.toml`: minimum 8 characters,
/// `lower_upper_letters_digits`). The server stays the authority; this only avoids needless round trips.
enum AuthValidation {
    static let minimumPasswordLength = 8

    static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Deliberately loose (`a@b.c`): real validation is the confirmation e-mail.
    static func isValidEmail(_ raw: String) -> Bool {
        let email = normalizedEmail(raw)
        guard !email.contains(where: \.isWhitespace) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }
}

/// Which parts of the password policy a password meets.
struct PasswordRules: Equatable, Sendable {
    let hasMinimumLength: Bool
    let hasLowercase: Bool
    let hasUppercase: Bool
    let hasDigit: Bool

    init(_ password: String) {
        hasMinimumLength = password.count >= AuthValidation.minimumPasswordLength
        hasLowercase = password.contains(where: \.isLowercase)
        hasUppercase = password.contains(where: \.isUppercase)
        hasDigit = password.contains(where: \.isNumber)
    }

    var isSatisfied: Bool { hasMinimumLength && hasLowercase && hasUppercase && hasDigit }

    var metCount: Int {
        [hasMinimumLength, hasLowercase, hasUppercase, hasDigit].filter { $0 }.count
    }
}

enum PasswordStrength: Int, Sendable, Comparable {
    case empty, weak, fair, strong

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Weak until the policy is met; strong once it is met and the password is long (12+) or has a symbol.
    init(_ password: String) {
        guard !password.isEmpty else { self = .empty; return }
        let rules = PasswordRules(password)
        guard rules.isSatisfied else { self = .weak; return }
        let hasSymbol = password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        self = (password.count >= 12 || hasSymbol) ? .strong : .fair
    }
}
