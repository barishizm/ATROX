import Testing

@testable import ATROX

struct LegalLinksTests {
    @Test func readsConfiguredURLs() {
        let links = LegalLinks(infoDictionary: [
            "LegalTermsURL": "https://example.com/terms",
            "LegalPrivacyURL": "https://example.com/privacy",
        ])
        #expect(links.terms?.absoluteString == "https://example.com/terms")
        #expect(links.privacy?.absoluteString == "https://example.com/privacy")
    }

    @Test(arguments: ["", "   ", "$(LEGAL_TERMS_URL)", "not a url", "javascript:alert(1)", "ftp://example.com/x"])
    func hidesLinkWhenNotUsable(_ value: String) {
        #expect(LegalLinks(infoDictionary: ["LegalTermsURL": value]).terms == nil)
    }

    @Test func hidesLinkWhenMissingOrWrongType() {
        #expect(LegalLinks(infoDictionary: [:]).terms == nil)
        #expect(LegalLinks(infoDictionary: ["LegalTermsURL": 42]).terms == nil)
    }
}
