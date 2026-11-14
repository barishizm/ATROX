import DataKit
import Foundation
import Testing

@testable import ATROX

@Suite struct InsightPresenterTests {
    private let en = Locale(identifier: "en")
    private let tr = Locale(identifier: "tr")
    private let names = ["bench": "Bench Press", "row": "Barbell Row"]

    private func insight(_ kind: InsightKind, subject: String = "bench", payload: InsightPayload) -> Insight {
        Insight(
            id: UUID(), kind: kind, subject: subject, severity: .mild, priority: 50, action: .askCoach, payload: payload,
            isActive: true, detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private var samples: [Insight] {
        [
            insight(.plateau, payload: InsightPayload(subjects: ["bench"], values: ["sessions": 9])),
            insight(.progressFast, payload: InsightPayload(subjects: ["bench"], values: ["observed_pct": 4.2, "expected_pct": 2.1])),
            insight(.progressSlow, payload: InsightPayload(subjects: ["bench"], values: ["observed_pct": 0.3, "expected_pct": 2.1])),
            insight(.neglectedMuscle, subject: "lats", payload: InsightPayload(subjects: ["lats"], muscles: ["lats"], values: ["weekly_average": 8.5])),
            insight(.pushPull, subject: "push_pull", payload: InsightPayload(values: ["push_sets": 40, "pull_sets": 18], variant: "pull_behind")),
            insight(.pushPull, subject: "push_pull", payload: InsightPayload(values: ["push_sets": 12, "pull_sets": 30], variant: "push_behind")),
            insight(.comeback, subject: "global", payload: InsightPayload(values: ["days": 21])),
            insight(.bodyweightStale, subject: "global", payload: InsightPayload(values: ["days": 90])),
            insight(.repRangeStuck, subject: "global", payload: InsightPayload(values: ["share": 0.91], variant: "strength")),
            insight(.repRangeStuck, subject: "global", payload: InsightPayload(values: ["share": 0.91], variant: "hypertrophy")),
            insight(.repRangeStuck, subject: "global", payload: InsightPayload(values: ["share": 0.91], variant: "endurance")),
            insight(.imbalance, subject: "ratio_rule.push_pull", payload: InsightPayload(subjects: ["row"], variant: "ratio_rule.push_pull.pull_behind")),
            insight(.imbalance, subject: "ratio_rule.squat_deadlift", payload: InsightPayload(variant: "ratio_rule.squat_deadlift.hinge_behind")),
            insight(.imbalance, subject: "conditional_residual.bench", payload: InsightPayload(variant: "conditional_residual.bench.below_expected")),
            insight(.imbalance, subject: "conditional_residual.squat", payload: InsightPayload(variant: "conditional_residual.squat.above_expected")),
            insight(.imbalance, subject: "left_right.row", payload: InsightPayload(subjects: ["row"], values: ["magnitude": 0.12], variant: "left_right.left_behind")),
            insight(.imbalance, subject: "other", payload: InsightPayload(variant: "something.new")),
        ]
    }

    @Test func everyInsightHasResolvedTextInBothLanguages() {
        for locale in [en, tr] {
            for sample in samples {
                let item = InsightPresenter.item(for: sample, names: names, locale: locale)
                for text in [item.title, item.body, item.actionTitle, item.coachPrompt] {
                    #expect(!text.isEmpty)
                    #expect(!text.contains("insight."), "unresolved key in \(locale.identifier): \(text)")
                    #expect(!text.contains("%@") && !text.contains("%lld") && !text.contains("$@"), "unfilled format in \(locale.identifier): \(text)")
                }
            }
        }
    }

    @Test func textNamesTheSubjectAndKeepsNumbers() {
        let plateau = InsightPresenter.item(for: samples[0], names: names, locale: en)
        #expect(plateau.title.contains("Bench Press"))
        #expect(plateau.body.contains("9"))
        let pace = InsightPresenter.item(for: samples[1], names: names, locale: en)
        #expect(pace.body.contains("+4.2 %") && pace.body.contains("+2.1 %"))
        let neglected = InsightPresenter.item(for: samples[3], names: names, locale: tr)
        #expect(neglected.title.contains("Kol") == false && neglected.body.contains("8,5"))
        let side = InsightPresenter.item(for: samples[15], names: names, locale: en)
        #expect(side.title.contains("left") && side.title.contains("Barbell Row") && side.body.contains("12 %"))
    }

    @Test func pushPullTitleFollowsTheWeakSideAndRatioNamesBothGroups() {
        let pull = InsightPresenter.item(for: samples[4], names: names, locale: en)
        let push = InsightPresenter.item(for: samples[5], names: names, locale: en)
        #expect(pull.title != push.title && pull.title.contains("Pulling"))
        let ratio = InsightPresenter.item(for: samples[11], names: names, locale: en)
        #expect(ratio.title.contains("pulling") && ratio.title.contains("pushing"))
    }

    @Test func coachPromptQuotesTheTitle() {
        let item = InsightPresenter.item(for: samples[0], names: names, locale: en)
        #expect(item.coachPrompt.contains(item.title))
    }

    @Test func eachKindHasAnIconAndAnAction() {
        for kind in InsightKind.allCases {
            let sample = samples.first { $0.kind == kind }
            #expect(sample != nil, "no sample for \(kind)")
            if let sample { #expect(!InsightPresenter.item(for: sample, names: names, locale: en).icon.isEmpty) }
        }
    }
}
