import DataKit
import Foundation
import Observation

/// State of the Friends screens (P086): social on/off, friends, requests, blocks, search and the profile form.
@MainActor
@Observable
final class SocialModel {
    enum Phase: Equatable {
        case loading
        case failed
        /// No public profile: the join screen is shown. Nothing is shared.
        case off
        case on
    }

    enum UsernameStatus: Equatable {
        case idle
        case invalid(SocialTextPolicy.UsernameIssue)
        case checking
        case available
        case taken
    }

    private(set) var phase: Phase = .loading
    private(set) var profile: SocialProfile?
    private(set) var connections: [SocialPerson] = []
    private(set) var results: [SocialPerson] = []
    private(set) var usernameStatus: UsernameStatus = .idle
    /// A `Localizable` key for the last failure; cleared by the next successful action.
    private(set) var errorKey: String?
    private(set) var isBusy = false
    private(set) var searched = false
    private(set) var invite: InviteState = .loading

    /// What an invite link leads to (P088).
    enum InviteState: Equatable {
        case loading
        case failed
        /// I have no profile yet: joining comes first.
        case needsProfile
        case itsMe
        case notFound
        case person(SocialPerson)
    }

    @ObservationIgnored private let service: any SocialService

    init(service: any SocialService) { self.service = service }

    // MARK: Derived lists

    var friends: [SocialPerson] { connections.filter { $0.relation == .friend } }
    var incoming: [SocialPerson] { connections.filter { $0.relation == .incoming } }
    var outgoing: [SocialPerson] { connections.filter { $0.relation == .outgoing } }
    var blocked: [SocialPerson] { connections.filter { $0.relation == .blocked } }

    /// Friends tab states: no friends and no requests yet.
    var isEmpty: Bool { friends.isEmpty && incoming.isEmpty && outgoing.isEmpty }

    // MARK: Loading

    func load() async {
        if phase != .on { phase = .loading }
        do {
            profile = try await service.myProfile()
            guard profile != nil else {
                connections = []
                phase = .off
                return
            }
            connections = try await service.connections()
            phase = .on
        } catch {
            if phase == .loading { phase = .failed } else { errorKey = Self.key(error) }
        }
    }

    // MARK: Profile

    /// Instant availability feedback: format rules locally, then the server (the caller debounces).
    func checkUsername(_ raw: String) async {
        let name = SocialTextPolicy.canonical(raw)
        if name.isEmpty {
            usernameStatus = .idle
            return
        }
        if let issue = SocialTextPolicy.usernameIssue(name) {
            usernameStatus = .invalid(issue)
            return
        }
        if name == profile?.username {
            usernameStatus = .available
            return
        }
        usernameStatus = .checking
        let available = try? await service.usernameAvailable(name)
        // A newer keystroke may have replaced this answer while the request was in flight.
        guard name == SocialTextPolicy.canonical(raw) else { return }
        usernameStatus = available == true ? .available : (available == false ? .taken : .idle)
    }

    @discardableResult
    func save(_ draft: SocialProfile) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            profile = try await service.saveProfile(draft)
            errorKey = nil
            await load()
            return true
        } catch {
            errorKey = Self.key(error)
            if case SocialError.usernameTaken = error { usernameStatus = .taken }
            return false
        }
    }

    /// "Turn social off": deletes the profile and every friendship.
    func turnOff() async {
        await perform { try await self.service.deleteProfile() }
        if errorKey == nil {
            profile = nil
            connections = []
            results = []
            phase = .off
        }
    }

    // MARK: Invite links

    /// Resolves the username in an invite link into someone I can send a request to.
    func loadInvite(_ username: String) async {
        invite = .loading
        await load()
        switch phase {
        case .loading, .failed: invite = .failed
        case .off: invite = .needsProfile
        case .on:
            let name = SocialTextPolicy.canonical(username)
            if name == profile?.username { invite = .itsMe; return }
            do {
                invite = try await service.resolveInvite(name).map { .person($0) } ?? .notFound
            } catch {
                invite = .failed
            }
        }
    }

    func sendInviteRequest(to person: SocialPerson) async {
        await perform { _ = try await self.service.sendRequest(to: person.id) }
        if errorKey == nil { await loadInvite(person.username) }
    }

    /// The service behind this model, for screens that need their own calls (the ranking).
    var socialService: any SocialService { service }

    // MARK: Search and requests

    func search(_ query: String) async {
        let text = SocialTextPolicy.canonical(query)
        guard text.count >= 2 else {
            results = []
            searched = false
            return
        }
        do {
            results = try await service.search(text)
            searched = true
            errorKey = nil
        } catch {
            errorKey = Self.key(error)
        }
    }

    func sendRequest(to person: SocialPerson) async {
        await perform { _ = try await self.service.sendRequest(to: person.id) }
        await search(person.username)
    }

    func respond(to person: SocialPerson, accept: Bool) async {
        await perform { try await self.service.respond(to: person.id, accept: accept) }
    }

    func remove(_ person: SocialPerson) async { await perform { try await self.service.removeFriend(person.id) } }
    func block(_ person: SocialPerson) async { await perform { try await self.service.block(person.id) } }
    func unblock(_ person: SocialPerson) async { await perform { try await self.service.unblock(person.id) } }

    func report(_ person: SocialPerson, reason: ReportReason, note: String?) async -> Bool {
        await perform { try await self.service.report(person.id, reason: reason, note: note) }
        return errorKey == nil
    }

    func clearError() { errorKey = nil }

    // MARK: Plumbing

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            errorKey = nil
            if phase == .on { connections = (try? await service.connections()) ?? connections }
        } catch {
            errorKey = Self.key(error)
        }
    }

    nonisolated static func key(_ error: Error) -> String {
        switch error as? SocialError {
        case .usernameTaken: "social.error.taken"
        case .invalidUsername: "social.error.username"
        case .invalidDisplayName: "social.error.displayname"
        case .rateLimited: "social.error.rate"
        case .blocked: "social.error.blocked"
        default: "social.error.generic"
        }
    }
}
