import Testing

@testable import ATROX

struct AuthValidationTests {
    @Test(arguments: ["a@b.co", "  Name.Surname+tag@Example.COM ", "x@sub.domain.org"])
    func acceptsPlausibleEmails(_ email: String) {
        #expect(AuthValidation.isValidEmail(email))
    }

    @Test(arguments: ["", "plain", "@b.co", "a@", "a@b", "a@b.", "a@.co", "a b@c.de", "a@@b.co", "a@b..co"])
    func rejectsMalformedEmails(_ email: String) {
        #expect(!AuthValidation.isValidEmail(email))
    }

    @Test func normalizesEmail() {
        #expect(AuthValidation.normalizedEmail("  Foo@Bar.COM\n") == "foo@bar.com")
    }

    @Test func rulesMatchServerPolicy() {
        #expect(PasswordRules("Abcdef12").isSatisfied)
        #expect(!PasswordRules("abcdef12").isSatisfied)  // no uppercase
        #expect(!PasswordRules("ABCDEF12").isSatisfied)  // no lowercase
        #expect(!PasswordRules("Abcdefgh").isSatisfied)  // no digit
        #expect(!PasswordRules("Abcde12").isSatisfied)  // too short
        #expect(PasswordRules("Abcde12").metCount == 3)
    }

    @Test func strengthLevels() {
        #expect(PasswordStrength("") == .empty)
        #expect(PasswordStrength("abc") == .weak)
        #expect(PasswordStrength("abcdefgh1") == .weak)  // policy not met
        #expect(PasswordStrength("Abcdef12") == .fair)
        #expect(PasswordStrength("Abcdef12!") == .strong)
        #expect(PasswordStrength("Abcdefghijk1") == .strong)
        #expect(PasswordStrength("Abcdef12") < PasswordStrength("Abcdef12!"))
    }
}
