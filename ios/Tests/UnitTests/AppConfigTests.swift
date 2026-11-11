import Foundation
import Testing

@testable import GymAnalyzer

struct AppConfigTests {
    @Test func bundleIdentifierComesFromConfig() {
        let id = Bundle.main.bundleIdentifier ?? ""
        #expect(id.hasPrefix("com.barishizm.vesania"))
    }

    @Test func environmentKeyIsPresent() {
        let env = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String
        #expect(env == "local")
    }
}
