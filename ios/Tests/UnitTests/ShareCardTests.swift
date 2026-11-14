import SwiftUI
import Testing

@testable import ATROX

@MainActor
@Suite struct ShareCardTests {
    private let samples: [ShareCardContent] = [
        .overall(score: 71.6, level: "Advanced", reference: "vs. gym-goers like you", name: "Ada", bodyweight: "70 kg"),
        .exercise(
            name: "Bench Press", score: 64, level: "Intermediate", reference: "vs. gym-goers like you", e1rm: "100 kg", person: "Ada",
            bodyweight: "70 kg"
        ),
        .record(exercise: "Squat", kindLabel: "Weight record", value: "140 kg", name: "Ada"),
        .weekly(period: "10–16 Nov", workouts: 3, goal: 4, sets: 36, records: 1, score: 55, level: "Intermediate", name: nil)
    ]

    @Test func everyTemplateRendersAtBothSizesInBothLanguages() throws {
        for content in samples {
            for format in ShareCardOptions.Format.allCases {
                for locale in [Locale(identifier: "en"), Locale(identifier: "tr")] {
                    let options = ShareCardOptions(format: format)
                    let image = try #require(ShareCardRenderer.image(content: content, options: options, locale: locale))
                    #expect(Int(image.size.width * image.scale) == 1080)
                    #expect(Int(image.size.height * image.scale) == (format == .story ? 1920 : 1080))
                }
            }
        }
    }

    @Test func templatesCoverEveryKind() {
        #expect(Set(samples.map(\.kind)) == Set(ShareCardContent.Kind.allCases))
    }

    @Test func bodyweightIsHiddenByDefaultAndScoresAreClamped() {
        #expect(ShareCardOptions().showsBodyweight == false)
        #expect(samples[0].score == 72)
        #expect(ShareCardContent.overall(score: 130, level: "", reference: nil, name: nil, bodyweight: nil).score == 99)
        #expect(ShareCardContent.overall(score: -4, level: "", reference: nil, name: nil, bodyweight: nil).score == 1)
    }

    @Test func weeklyCardOmitsRecordsStatWithoutRecords() {
        let card = ShareCardContent.weekly(period: "p", workouts: 2, goal: 0, sets: 20, records: 0, score: nil, level: nil, name: nil)
        #expect(card.stats.map(\.label) == ["share.stat.workouts", "share.stat.sets"])
        #expect(card.stats.first?.value == "2")
    }
}
