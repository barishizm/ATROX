@testable import DataKit
import Foundation
import Testing

@Suite("Analytics (P100)")
struct AnalyticsTests {
    private func make(now: TestClock = TestClock()) -> (AnalyticsService, RecordingAnalytics, InMemoryAnalyticsStorage, TestClock) {
        let sink = RecordingAnalytics()
        let storage = InMemoryAnalyticsStorage()
        return (AnalyticsService(sink: sink, storage: storage, clock: now.closure), sink, storage, now)
    }

    @Test func eventNamesAreUniqueAndNamespaced() {
        let all: [AnalyticsEvent] = [
            .signUpCompleted(method: .apple), .onboardingCompleted, .firstWorkoutFinished, .firstScoreViewed, .day7Return,
            .coachMessageSent, .coachSuggestionDecided(.applied), .shareCompleted(target: .shareSheet),
            .referenceGroupChanged(group: .gym), .paywallViewed(source: .coach), .trialStarted(plan: .yearly),
            .subscriptionStarted(plan: .monthly),
        ]
        #expect(Set(all.map(\.name)).count == all.count)
        #expect(all.allSatisfy { $0.name.hasPrefix("atrox.") })
    }

    @Test func parametersCarryOnlyCategoryValuesFromTheFixedEnums() {
        let allowed: Set<String> = Set(
            AnalyticsEvent.SignInMethod.allCases.map(\.rawValue) + AnalyticsEvent.CoachDecision.allCases.map(\.rawValue)
            + AnalyticsEvent.ShareTarget.allCases.map(\.rawValue) + AnalyticsEvent.ReferenceGroup.allCases.map(\.rawValue)
            + AnalyticsEvent.PaywallSource.allCases.map(\.rawValue) + AnalyticsEvent.SubscriptionPlan.allCases.map(\.rawValue)
        )
        let samples: [AnalyticsEvent] = [
            .signUpCompleted(method: .email), .coachSuggestionDecided(.rejected), .shareCompleted(target: .saveImage),
            .referenceGroupChanged(group: .competitor), .paywallViewed(source: .history), .trialStarted(plan: .monthly),
        ]
        for event in samples {
            #expect(!event.parameters.isEmpty)
            #expect(event.parameters.values.allSatisfy(allowed.contains), "\(event.name)")
        }
    }

    @Test func disabledSendsNothing() {
        let (service, sink, _, _) = make()
        service.isEnabled = false
        service.send(.coachMessageSent)
        service.appLaunched()
        #expect(sink.events.isEmpty)
        service.isEnabled = true
        service.send(.coachMessageSent)
        #expect(sink.events == [.coachMessageSent])
    }

    @Test func enabledByDefault() {
        #expect(make().0.isEnabled)
    }

    @Test func milestonesFireOncePerInstallButFeatureEventsRepeat() {
        let (service, sink, _, _) = make()
        service.send(.onboardingCompleted)
        service.send(.onboardingCompleted)
        service.send(.coachMessageSent)
        service.send(.coachMessageSent)
        #expect(sink.events == [.onboardingCompleted, .coachMessageSent, .coachMessageSent])
    }

    @Test func day7ReturnFiresOnceAfterSevenDays() {
        let (service, sink, _, clock) = make()
        service.appLaunched()                       // first launch is recorded, nothing sent
        clock.advance(by: 6 * 86_400)
        service.appLaunched()
        #expect(sink.events.isEmpty)
        clock.advance(by: 2 * 86_400)
        service.appLaunched()
        service.appLaunched()
        #expect(sink.events == [.day7Return])
    }
}
