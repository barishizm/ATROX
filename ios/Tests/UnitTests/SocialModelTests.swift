import DataKit
import Foundation
import Testing

@testable import ATROX

@MainActor
@Suite struct SocialModelTests {
    private let bob = SocialPerson(id: UUID(), username: "bob_lifts", displayName: "Bob", relation: .none)
    private let carol = SocialPerson(id: UUID(), username: "carol", displayName: "Carol", relation: .incoming)

    private func model(profile: SocialProfile? = nil) -> SocialModel {
        SocialModel(service: FakeSocialService(profile: profile, people: [bob, carol]))
    }

    private let me = SocialProfile(username: "me_lifts", displayName: "Me")

    @Test func startsOffWithoutProfile() async {
        let model = model()
        await model.load()
        #expect(model.phase == .off)
        #expect(model.connections.isEmpty)
    }

    @Test func serviceFailureOnFirstLoadShowsFailedState() async {
        let service = FakeSocialService()
        await service.setFailure(.failed)
        let model = SocialModel(service: service)
        await model.load()
        #expect(model.phase == .failed)
    }

    @Test func joiningTurnsSocialOnWithBothSwitchesOffByDefault() async {
        let model = model()
        await model.load()
        await model.checkUsername("Me_Lifts")
        #expect(model.usernameStatus == .available)
        #expect(await model.save(SocialProfile(username: "Me_Lifts", displayName: " Me ")))
        #expect(model.phase == .on)
        #expect(model.profile?.username == "me_lifts")
        #expect(model.profile?.isDiscoverable == false)
        #expect(model.profile?.sharesScore == false)
        // Carol's incoming request is the only connection: friends are empty but requests are not.
        #expect(model.incoming.map(\.username) == ["carol"])
        #expect(model.isEmpty == false)
    }

    @Test func usernameFeedbackIsInstantForBadNamesAndAsksTheServerForGoodOnes() async {
        let model = SocialModel(service: FakeSocialService(takenUsernames: ["alice"]))
        await model.checkUsername("")
        #expect(model.usernameStatus == .idle)
        await model.checkUsername("ab")
        #expect(model.usernameStatus == .invalid(.tooShort))
        await model.checkUsername("admin")
        #expect(model.usernameStatus == .invalid(.reserved))
        await model.checkUsername("alice")
        #expect(model.usernameStatus == .taken)
    }

    @Test func requestAcceptAndRemoveFlow() async {
        let model = model(profile: me)
        await model.load()
        await model.search("bob")
        #expect(model.results.first?.relation == SocialRelation.none)
        await model.sendRequest(to: bob)
        #expect(model.outgoing.map(\.username) == ["bob_lifts"])
        #expect(model.results.first?.relation == .outgoing)
        await model.respond(to: carol, accept: true)
        #expect(model.friends.map(\.username) == ["carol"])
        await model.remove(carol)
        #expect(model.friends.isEmpty)
    }

    @Test func blockingHidesFromSearchAndListsInBlocked() async {
        let model = model(profile: me)
        await model.load()
        await model.block(bob)
        #expect(model.blocked.map(\.username) == ["bob_lifts"])
        await model.search("bob")
        #expect(model.results.isEmpty)
        await model.unblock(bob)
        #expect(model.blocked.isEmpty)
    }

    @Test func reportIsRecordedAndFailureSurfacesAKey() async {
        let service = FakeSocialService(profile: me, people: [bob])
        let model = SocialModel(service: service)
        await model.load()
        #expect(await model.report(bob, reason: .spam, note: "x"))
        #expect(await service.reports.count == 1)
        await service.setFailure(.rateLimited)
        #expect(await model.report(bob, reason: .spam, note: nil) == false)
        #expect(model.errorKey == "social.error.rate")
    }

    @Test func turningSocialOffDeletesEverything() async {
        let model = model(profile: me)
        await model.load()
        await model.respond(to: carol, accept: true)
        await model.turnOff()
        #expect(model.phase == .off)
        #expect(model.profile == nil)
        #expect(model.connections.isEmpty)
    }
}
