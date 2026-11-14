import Foundation
import Testing

@testable import ATROX

@MainActor
@Suite struct DeepLinkRouterTests {
    private let config = DeepLink.Configuration(host: "Links.Example.com", scheme: "atrox")

    private func link(_ string: String) -> DeepLink? { DeepLink(url: URL(string: string)!, configuration: config) }

    @Test func universalInviteLinkResolvesToFriendInvite() {
        #expect(link("https://links.example.com/u/Iron_Mike") == .friendInvite(username: "iron_mike"))
        #expect(link("https://links.example.com/u/iron_mike/") == .friendInvite(username: "iron_mike"))
    }

    @Test func schemeLinksResolveToTypedRoutes() {
        #expect(link("atrox://u/alice") == .friendInvite(username: "alice"))
        #expect(link("atrox://today") == .tab(.today))
        #expect(link("atrox://coach") == .tab(.coach))
        #expect(link("atrox://weekly") == .weeklySummary)
    }

    @Test func foreignAndMalformedLinksAreIgnored() {
        #expect(link("https://evil.example.org/u/alice") == nil)
        #expect(link("https://links.example.com/privacy") == nil)
        #expect(link("https://links.example.com/u/") == nil)
        #expect(link("https://links.example.com/u/ab") == nil)
        #expect(link("https://links.example.com/u/admin") == nil)
        #expect(link("https://links.example.com/u/a/b") == nil)
        #expect(link("atrox://login-callback?code=1") == nil)
        #expect(link("com.googleusercontent.apps.123:/oauth") == nil)
    }

    @Test func unconfiguredHostAcceptsNoWebLinks() {
        let none = DeepLink.Configuration(host: "$(APP_LINK_HOST)", scheme: "atrox")
        #expect(none.host == nil)
        #expect(DeepLink(url: URL(string: "https://links.example.com/u/alice")!, configuration: none) == nil)
        #expect(DeepLink.inviteLink(username: "alice", configuration: none) == nil)
    }

    @Test func inviteLinkRoundTrips() throws {
        let url = try #require(DeepLink.inviteLink(username: " Alice ", configuration: config))
        #expect(url.absoluteString == "https://links.example.com/u/alice")
        #expect(DeepLink(url: url, configuration: config) == .friendInvite(username: "alice"))
        #expect(DeepLink.tab(.today).url(scheme: "atrox")?.absoluteString == "atrox://today")
    }

    @Test func linkWaitsInTheRouterUntilConsumed() {
        let router = DeepLinkRouter()
        #expect(router.receive(url: URL(string: "https://links.example.com/u/alice")!, configuration: config))
        #expect(router.pending == .friendInvite(username: "alice"))
        #expect(router.consume() == .friendInvite(username: "alice"))
        #expect(router.pending == nil)
        #expect(router.receive(url: URL(string: "atrox://login-callback")!, configuration: config) == false)
        #expect(router.pending == nil)
    }

    @Test func notificationTapUsesTheSameRoute() {
        let router = DeepLinkRouter()
        router.receive(.weeklySummary)
        #expect(router.consume() == .weeklySummary)
    }
}
