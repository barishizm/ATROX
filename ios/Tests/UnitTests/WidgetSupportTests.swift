import DataKit
import Foundation
import Testing

@testable import ATROX

private func makeDefaults() -> UserDefaults {
    let name = "widget-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let routineId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let dayA = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
private let dayB = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func plannedDay(_ id: UUID, name: String) -> WidgetSnapshot.PlannedDay {
    WidgetSnapshot.PlannedDay(routineId: routineId, dayId: id, routineName: "Upper / Lower", dayName: name, exerciseCount: 6)
}

private func snapshot(weekEndsAt: Date = t0.addingTimeInterval(3 * 86_400), score: WidgetSnapshot.Score? = .init(value: 72, isProvisional: false, change: 3)) -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAt: t0, score: score, next: plannedDay(dayA, name: "Upper A"),
        days: [plannedDay(dayA, name: "Upper A"), plannedDay(dayB, name: "Lower A")],
        weeklyDone: 2, weeklyGoal: 4, streakWeeks: 5, trainedToday: false, weekEndsAt: weekEndsAt
    )
}

@Suite struct WidgetSnapshotTests {
    @Test func roundTripsThroughTheStore() {
        let store = WidgetSnapshotStore(defaults: makeDefaults())
        #expect(store.read() == nil)
        #expect(store.write(snapshot()))
        #expect(store.read() == snapshot())
    }

    @Test func writingTheSameContentAgainDoesNotAskForAReload() {
        let store = WidgetSnapshotStore(defaults: makeDefaults())
        store.write(snapshot())
        var later = snapshot()
        later.generatedAt = t0.addingTimeInterval(600)
        #expect(!store.write(later))
        var changed = snapshot()
        changed.weeklyDone = 3
        #expect(store.write(changed))
        #expect(store.read()?.weeklyDone == 3)
    }

    @Test func clearingMakesTheWidgetsSignedOut() {
        let store = WidgetSnapshotStore(defaults: makeDefaults())
        store.write(snapshot())
        store.clear()
        #expect(store.read() == nil)
        #expect(WidgetContentState(store.read()) == .signedOut)
    }

    @Test func aSnapshotFromAnotherVersionIsIgnored() {
        let defaults = makeDefaults()
        let store = WidgetSnapshotStore(defaults: defaults)
        var future = snapshot()
        future.version = WidgetSnapshot.currentVersion + 1
        store.write(future)
        #expect(store.read() == nil)
        defaults.set(Data("not json".utf8), forKey: WidgetSnapshotStore.key)
        #expect(store.read() == nil)
    }

    @Test func weeklyCountResetsWhenTheWeekHasEnded() {
        let s = snapshot()
        #expect(s.weeklyDone(at: t0) == 2)
        #expect(s.weeklyProgress(at: t0) == 0.5)
        let afterWeek = s.weekEndsAt.addingTimeInterval(1)
        #expect(s.weeklyDone(at: afterWeek) == 0)
        #expect(s.weeklyProgress(at: afterWeek) == 0)
        var met = s
        met.weeklyDone = 6
        #expect(met.weeklyProgress(at: t0) == 1)
        var noGoal = s
        noGoal.weeklyGoal = 0
        #expect(noGoal.weeklyProgress(at: t0) == 0)
    }

    @Test func contentStateDistinguishesSignedOutNoScoreAndReady() {
        #expect(WidgetContentState(nil) == .signedOut)
        #expect(WidgetContentState(snapshot(score: nil)) == .noScore)
        #expect(WidgetContentState(snapshot()) == .ready)
    }

    @Test func findsADayInTheProgramOrAsTheNextWorkout() {
        let s = snapshot()
        #expect(s.day(id: dayB)?.dayName == "Lower A")
        #expect(s.day(id: UUID()) == nil)
    }
}

@Suite struct WidgetTimelinePlanTests {
    @Test func refreshesSeveralTimesADay() {
        let plan = WidgetTimelinePlan.plan(for: snapshot(), now: t0)
        #expect(plan.entryDates.first == t0)
        #expect(plan.reloadAfter == t0.addingTimeInterval(6 * 3600))
        #expect(plan.entryDates.count == 1)
    }

    @Test func addsAnEntryAtTheWeekRolloverWhenItIsNear() {
        let end = t0.addingTimeInterval(2 * 3600)
        let plan = WidgetTimelinePlan.plan(for: snapshot(weekEndsAt: end), now: t0)
        #expect(plan.entryDates == [t0, end])
    }

    @Test func worksWithoutASnapshot() {
        let plan = WidgetTimelinePlan.plan(for: nil, now: t0)
        #expect(plan.entryDates == [t0])
    }
}

@Suite struct WidgetLinkTests {
    @Test func widgetLinksParseBackToTheSameDeepLink() throws {
        let config = DeepLink.Configuration(host: nil, scheme: "atrox")
        let start = WidgetLink.startWorkout(plannedDay(dayA, name: "Upper A"), scheme: "atrox")
        #expect(DeepLink(url: start, configuration: config) == .startWorkout(routineId: routineId, dayId: dayA))
        #expect(DeepLink(url: WidgetLink.tab("workout", scheme: "atrox"), configuration: config) == .tab(.workout))
        #expect(DeepLink(url: WidgetLink.tab("analysis", scheme: "atrox"), configuration: config) == .tab(.analysis))
        #expect(DeepLink(url: WidgetLink.tab("today", scheme: "atrox"), configuration: config) == .tab(.today))
        #expect(DeepLink.startWorkout(routineId: routineId, dayId: dayA).url(scheme: "atrox") == start)
    }

    @Test func malformedStartLinksAreIgnored() {
        let config = DeepLink.Configuration(host: nil, scheme: "atrox")
        for string in ["atrox://start", "atrox://start/x/y", "atrox://start/\(routineId.uuidString)", "atrox://start/\(routineId.uuidString)/\(dayA.uuidString)/extra"] {
            #expect(DeepLink(url: URL(string: string)!, configuration: config) == nil)
        }
    }

    @Test func unresolvedSchemeFallsBackToTheDefault() {
        #expect(WidgetLink.scheme(info: ["AppURLScheme": "$(APP_URL_SCHEME)"]) == "atrox")
        #expect(WidgetLink.scheme(info: ["AppURLScheme": "Custom"]) == "custom")
        #expect(WidgetLink.scheme(info: nil) == "atrox")
    }
}

@MainActor
@Suite struct IntentTests {
    @Test func startWorkoutPicksTheChosenDayThenTheNextOneThenTheTab() {
        let s = snapshot()
        let chosen = StartWorkoutIntent.link(day: dayB, snapshot: s)
        #expect(chosen.absoluteString.hasSuffix("/\(dayB.uuidString)"))
        let next = StartWorkoutIntent.link(day: nil, snapshot: s)
        #expect(next.absoluteString.hasSuffix("/\(dayA.uuidString)"))
        // A day that is no longer in the program falls back to the next workout.
        #expect(StartWorkoutIntent.link(day: UUID(), snapshot: s) == next)
        #expect(StartWorkoutIntent.link(day: nil, snapshot: nil) == WidgetLink.tab("workout"))
        var noPlan = s
        noPlan.next = nil
        noPlan.days = []
        #expect(StartWorkoutIntent.link(day: nil, snapshot: noPlan) == WidgetLink.tab("workout"))
    }

    @Test func entityQueryOffersTheProgramDays() {
        let entity = WorkoutDayEntity(plannedDay(dayB, name: "Lower A"))
        #expect(entity.id == dayB)
        #expect(entity.dayName == "Lower A")
        #expect(entity.routineName == "Upper / Lower")
    }

    @Test func linksGoStraightToARunningAppAndWaitInTheInboxOtherwise() {
        let center = IntentCommandCenter()
        let inbox = PendingLinkInbox(defaults: makeDefaults())
        let url = URL(string: "atrox://workout")!
        center.deliver(url, inbox: inbox)
        #expect(inbox.take() == url)
        var received: [URL] = []
        center.openLink = { received.append($0) }
        center.deliver(url, inbox: inbox)
        #expect(received == [url])
        #expect(inbox.take() == nil)
    }

    @Test func inboxDropsOldLinksAndEmptiesItself() {
        let inbox = PendingLinkInbox(defaults: makeDefaults())
        let url = URL(string: "atrox://today")!
        inbox.post(url, at: t0)
        #expect(inbox.take(now: t0.addingTimeInterval(PendingLinkInbox.maxAge + 1)) == nil)
        inbox.post(url, at: t0)
        #expect(inbox.take(now: t0.addingTimeInterval(5)) == url)
        #expect(inbox.take(now: t0.addingTimeInterval(5)) == nil)
    }

    @Test func weightEntryRejectsImplausibleValues() {
        #expect(WeightEntry.kilograms(82.46) == 82.5)
        #expect(WeightEntry.kilograms(19.9) == nil)
        #expect(WeightEntry.kilograms(501) == nil)
        #expect(WeightEntry.kilograms(.nan) == nil)
        #expect(WeightEntry.kilograms(.infinity) == nil)
    }

    @Test func loggingAWeightNeedsASignedInUser() async throws {
        let store = try DataStore.inMemory()
        let container = AppContainer(sessionService: PlaceholderSessionService(), modelContainer: store)
        #expect(await container.logWeight(kilograms: 80) == .signedOut)
        container.debugSignIn()
        #expect(await container.logWeight(kilograms: 80.5, now: t0) == .saved)
        let userId = try #require(await container.currentUser()?.id)
        let latest = try await SwiftDataMeasurementRepository(modelContainer: store).latest(userId: userId)
        #expect(latest?.input.weightKg == 80.5)
        #expect(await AppContainer(sessionService: PlaceholderSessionService()).logWeight(kilograms: 80) == .failed)
    }
}
