import Testing

@testable import ATROX

struct FeatureFlagsTests {
    @Test func everyFlagHasALocalDefault() {
        for flag in FeatureFlag.allCases {
            #expect(FeatureFlags.localDefaults[flag] != nil, "\(flag) has no default")
        }
    }

    @Test func overridesBeatDefaults() {
        let flags = FeatureFlags(overrides: [.social: true])
        #expect(flags.isEnabled(.social))
        #expect(FeatureFlags().isEnabled(.social) == false)
    }

    @Test func remoteValuesLayerOnTop() {
        let flags = FeatureFlags().applying(remote: [.coach: false])
        #expect(flags.isEnabled(.coach) == false)
        #expect(flags.isEnabled(.paywall))
    }
}
