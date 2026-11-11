@testable import DataKit
import Foundation
import Testing

@Suite struct ConsentServiceTests {
    private let clock = TestClock()

    private func make(
        versions: ConsentVersions = .current, repo: SwiftDataConsentRepository? = nil
    ) throws -> (ConsentService, SwiftDataConsentRepository) {
        let repository = try repo ?? SwiftDataConsentRepository(modelContainer: DataStore.inMemory(), clock: clock.closure)
        return (ConsentService(repository: repository, versions: versions), repository)
    }

    @Test func freshUserNeedsEverything() async throws {
        let (service, _) = try make()
        #expect(try await service.needsLegalAcceptance(userId: testUser))
        #expect(try await service.status(of: .mlContribution, userId: testUser) == .notAsked)
        #expect(try await service.needsContributionDecision(userId: testUser))
        #expect(try await !service.isContributing(userId: testUser))  // not asked is never a yes
    }

    @Test func acceptingLegalRecordsBothKindsWithTheirVersions() async throws {
        let (service, repo) = try make(versions: ConsentVersions(terms: "t3", privacy: "p2"))
        try await service.acceptLegal(userId: testUser)
        #expect(try await !service.needsLegalAcceptance(userId: testUser))
        #expect(try await repo.current(kind: .terms, userId: testUser)?.version == "t3")
        #expect(try await repo.current(kind: .privacy, userId: testUser)?.version == "p2")
    }

    @Test func acceptingTwiceDoesNotAppendDuplicates() async throws {
        let (service, repo) = try make()
        try await service.acceptLegal(userId: testUser)
        try await service.acceptLegal(userId: testUser)
        #expect(try await repo.history(userId: testUser).count == 2)
    }

    @Test func newTermsVersionAsksAgainWhilePrivacyStaysAccepted() async throws {
        let (v1, repo) = try make()
        try await v1.acceptLegal(userId: testUser)
        clock.advance(by: 60)  // "latest row" is decided by timestamp
        let v2 = ConsentService(repository: repo, versions: ConsentVersions(terms: "2"))
        #expect(try await v2.needsLegalAcceptance(userId: testUser))
        #expect(try await v2.status(of: .terms, userId: testUser) == .outdated(previous: true))
        #expect(try await v2.status(of: .privacy, userId: testUser) == .granted)
        try await v2.acceptLegal(userId: testUser)
        #expect(try await !v2.needsLegalAcceptance(userId: testUser))
        #expect(try await repo.history(userId: testUser).count == 3)  // only terms was re-recorded
    }

    @Test func contributionYesAndNoAreBothRemembered() async throws {
        let (service, _) = try make()
        try await service.setContribution(true, userId: testUser)
        #expect(try await service.isContributing(userId: testUser))
        #expect(try await !service.needsContributionDecision(userId: testUser))
        try await service.setContribution(false, userId: otherUser)  // "Şimdi değil"
        #expect(try await service.status(of: .mlContribution, userId: otherUser) == .declined)
        #expect(try await !service.needsContributionDecision(userId: otherUser))
    }

    @Test func versionBumpAsksAgainWhetherTheAnswerWasYesOrNo() async throws {
        let (v1, repo) = try make()
        try await v1.setContribution(true, userId: testUser)
        try await v1.setContribution(false, userId: otherUser)
        clock.advance(by: 60)
        let v2 = ConsentService(repository: repo, versions: ConsentVersions(mlContribution: "2"))
        #expect(try await v2.status(of: .mlContribution, userId: testUser) == .outdated(previous: true))
        #expect(try await v2.status(of: .mlContribution, userId: otherUser) == .outdated(previous: false))
        #expect(try await v2.needsContributionDecision(userId: testUser))
        // An older yes no longer counts as consent for the new text.
        #expect(try await !v2.isContributing(userId: testUser))
        clock.advance(by: 60)
        try await v2.setContribution(true, userId: testUser)
        #expect(try await v2.isContributing(userId: testUser))
    }

    @Test func withdrawingKeepsTheHistoryAndStopsContribution() async throws {
        let (service, repo) = try make()
        try await service.setContribution(true, userId: testUser)
        clock.advance(by: 60)
        try await service.withdrawContribution(userId: testUser)
        #expect(try await !service.isContributing(userId: testUser))
        #expect(try await service.status(of: .mlContribution, userId: testUser) == .declined)
        #expect(try await repo.history(userId: testUser).map(\.granted) == [true, false])
    }

    @Test func withdrawingWithoutConsentWritesNothing() async throws {
        let (service, repo) = try make()
        try await service.withdrawContribution(userId: testUser)
        try await service.setContribution(false, userId: testUser)
        try await service.withdrawContribution(userId: testUser)
        #expect(try await repo.history(userId: testUser).count == 1)
    }

    @Test func aiSharingIsNotPartOfTheOnboardingConsents() async throws {
        let (service, repo) = try make()
        try await service.acceptLegal(userId: testUser)
        try await service.setContribution(true, userId: testUser)
        #expect(try await repo.current(kind: .aiSharing, userId: testUser) == nil)
    }

    @Test func historyIsNewestFirstAndKeepsWithdrawals() async throws {
        let (service, _) = try make()
        try await service.acceptLegal(userId: testUser)
        clock.advance(by: 10)
        try await service.setContribution(true, userId: testUser)
        clock.advance(by: 10)
        try await service.withdrawContribution(userId: testUser)
        let history = try await service.history(userId: testUser)
        #expect(history.count == 4)
        #expect(history.first?.kind == .mlContribution)
        #expect(history.first?.granted == false)
        #expect(history[1].granted)
        #expect(try await service.history(userId: otherUser).isEmpty)
    }
}
