import Foundation
import Testing
@testable import DesignSystem

@Suite struct ScoreLevelTests {
    @Test(arguments: [
        (0.0, ScoreLevel.beginner), (19.99, .beginner), (20, .developing), (39.9, .developing),
        (40, .intermediate), (59.9, .intermediate), (60, .advanced), (73, .advanced),
        (80, .expert), (94.9, .expert), (95, .elite), (100, .elite)
    ])
    func thresholdsMatchModelSpec(score: Double, expected: ScoreLevel) {
        #expect(ScoreLevel(score: score) == expected)
    }

    @Test func nonFiniteScoreFallsBackToBeginner() {
        #expect(ScoreLevel(score: .nan) == .beginner)
        #expect(ScoreLevel(score: .infinity) == .beginner)
    }

    @Test func explicitLocaleOverridesDeviceLanguage() {
        #expect(ScoreLevel.elite.localizedName(locale: Locale(identifier: "tr")) == "Elit")
        #expect(ScoreLevel.elite.localizedName(locale: Locale(identifier: "en")) == "Elite")
        #expect(ScoreLevel.beginner.localizedName(locale: Locale(identifier: "tr_TR")) == "Başlangıç")
    }

    @Test func ringClampsInput() {
        #expect(ScoreRing.clamped(-5) == 0)
        #expect(ScoreRing.clamped(140) == 100)
        #expect(ScoreRing.clamped(.nan) == 0)
        #expect(ScoreRing.clamped(73) == 73)
    }

    @Test(arguments: ["tr", "en"]) func everyLevelNameIsTranslated(locale: String) throws {
        let path = try #require(Bundle.module.path(forResource: locale, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let keys = ScoreLevel.allCases.map(\.localizationKey) + ["ds.scoreRing.a11yLabel", "ds.state.loading", "ds.errorState.title", "ds.errorState.retry"]
        for key in keys {
            let value = bundle.localizedString(forKey: key, value: "⚠️missing", table: nil)
            #expect(value != "⚠️missing" && value != key, "\(locale): \(key)")
        }
    }
}
