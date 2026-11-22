#if canImport(CryptoKit)
import Foundation
@testable import StrengthKit
import Testing

/// The app passes its `CFBundleShortVersionString` (the marketing version, `1.0`) as the running app version. A parse
/// failure there made the embedded model bundle unloadable, so no score was ever produced.
@Suite struct SemanticVersionTests {
    @Test func padsShortVersionsWithZeros() {
        #expect(SemanticVersion("1.0") == SemanticVersion("1.0.0"))
        #expect(SemanticVersion("2") == SemanticVersion("2.0.0"))
        #expect(SemanticVersion("1.2")?.description == "1.2.0")
    }

    @Test func rejectsMalformedVersions() {
        for text in ["", "a.b.c", "1.2.3.4", "1..2", "1.-2", "1.0."] {
            #expect(SemanticVersion(text) == nil, "\(text) should not parse")
        }
    }

    @Test func ordersNumerically() throws {
        let one = try #require(SemanticVersion("1.0"))
        let ten = try #require(SemanticVersion("1.10.0"))
        let two = try #require(SemanticVersion("1.2.0"))
        #expect(one < two)
        #expect(two < ten)
    }

    @Test func embeddedBundleLoadsWithTwoPartMarketingVersion() throws {
        let bundle = try ModelBundle.embedded(appVersion: "1.0")
        #expect(bundle.manifest.version == "1.0.0")
    }
}
#endif
