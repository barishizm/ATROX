@testable import DataKit
import Foundation
import Testing

@Suite("Analytics (P100)")
struct AnalyticsTests {
    private struct Rig {
        let service: AnalyticsService
        let sink: RecordingAnalytics
        let clock: TestClock
    }

    private func make() -> Rig {
        let sink = RecordingAnalytics()
        let clock = TestClock()
        return Rig(service: AnalyticsService(sink: sink, storage: InMemoryAnalyticsStorage(), clock: clock.closure), sink: sink, clock: clock)
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
        let rig = make()
        let (service, sink) = (rig.service, rig.sink)
        service.isEnabled = false
        service.send(.coachMessageSent)
        service.appLaunched()
        #expect(sink.events.isEmpty)
        service.isEnabled = true
        service.send(.coachMessageSent)
        #expect(sink.events == [.coachMessageSent])
    }

    @Test func enabledByDefault() {
        #expect(make().service.isEnabled)
    }

    @Test func milestonesFireOncePerInstallButFeatureEventsRepeat() {
        let rig = make()
        let (service, sink) = (rig.service, rig.sink)
        service.send(.onboardingCompleted)
        service.send(.onboardingCompleted)
        service.send(.coachMessageSent)
        service.send(.coachMessageSent)
        #expect(sink.events == [.onboardingCompleted, .coachMessageSent, .coachMessageSent])
    }

    @Test func day7ReturnFiresOnceAfterSevenDays() {
        let rig = make()
        let (service, sink, clock) = (rig.service, rig.sink, rig.clock)
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
