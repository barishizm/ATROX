import Foundation

/// Current version of every consent text. Bump a value when the wording or the data covered changes in a way
/// that needs a fresh decision; `ConsentService` then reports the kind as "needs asking" again.
public struct ConsentVersions: Sendable, Equatable {
    public var terms: String
    public var privacy: String
    public var mlContribution: String

    public init(terms: String = "1", privacy: String = "1", mlContribution: String = "1") {
        self.terms = terms
        self.privacy = privacy
        self.mlContribution = mlContribution
    }

    public static let current = ConsentVersions()

    func version(for kind: ConsentKind) -> String {
        switch kind {
        case .terms: terms
        case .privacy: privacy
        case .mlContribution: mlContribution
        case .aiSharing: "1"  // Asked by the coach on first open (P081), not here.
        }
    }
}

/// Where a consent kind stands for one user, judged against the current text version.
public enum ConsentStatus: Sendable, Equatable {
    /// Never answered.
    case notAsked
    /// Granted for the current version.
    case granted
    /// Declined, or withdrawn later, for the current version. Do not ask again until the version changes.
    case declined
    /// The last answer (either way) was given for an older text: ask again.
    case outdated(previous: Bool)

    public var needsAsking: Bool {
        switch self {
        case .notAsked, .outdated: true
        case .granted, .declined: false
        }
    }

    public var isGranted: Bool { self == .granted }
}

/// Reads and writes consent decisions on top of the append-only `ConsentRepository`.
///
/// - Terms and privacy are accepted together, in one tap; the app is not usable without them.
/// - ML contribution is opt-in with no default: `notAsked` is never treated as a yes.
/// - Withdrawing appends a `granted: false` row (the audit trail is kept) and never deletes anything.
public struct ConsentService: Sendable {
    private let repository: any ConsentRepository
    private let versions: ConsentVersions

    public init(repository: any ConsentRepository, versions: ConsentVersions = .current) {
        self.repository = repository
        self.versions = versions
    }

    public func status(of kind: ConsentKind, userId: UUID) async throws -> ConsentStatus {
        guard let latest = try await repository.current(kind: kind, userId: userId) else { return .notAsked }
        guard latest.version == versions.version(for: kind) else { return .outdated(previous: latest.granted) }
        return latest.granted ? .granted : .declined
    }

    /// True while terms or privacy has not been accepted at the current version.
    public func needsLegalAcceptance(userId: UUID) async throws -> Bool {
        let terms = try await status(of: .terms, userId: userId)
        let privacy = try await status(of: .privacy, userId: userId)
        return !(terms.isGranted && privacy.isGranted)
    }

    /// Records acceptance of the terms and the privacy policy. A kind that is already accepted at the current
    /// version is not written again (the user may revisit the screen with the back button).
    public func acceptLegal(userId: UUID) async throws {
        for kind in [ConsentKind.terms, .privacy] where try await !status(of: kind, userId: userId).isGranted {
            try await repository.record(kind: kind, version: versions.version(for: kind), granted: true, userId: userId)
        }
    }

    /// True when the contribution question has to be shown: never answered, or answered for an older text.
    public func needsContributionDecision(userId: UUID) async throws -> Bool {
        try await status(of: .mlContribution, userId: userId).needsAsking
    }

    /// Stores the answer to "Modeli birlikte geliştirelim" for the current version.
    public func setContribution(_ granted: Bool, userId: UUID) async throws {
        try await repository.record(
            kind: .mlContribution, version: versions.mlContribution, granted: granted, userId: userId
        )
    }

    /// Withdraws a previously given contribution consent. No-op if it is not currently granted.
    /// (Asking the server to delete the device's `contribution_key` data comes with the sync/contribute work.)
    public func withdrawContribution(userId: UUID) async throws {
        guard try await status(of: .mlContribution, userId: userId).isGranted else { return }
        try await setContribution(false, userId: userId)
    }

    public func isContributing(userId: UUID) async throws -> Bool {
        try await status(of: .mlContribution, userId: userId).isGranted
    }
}
