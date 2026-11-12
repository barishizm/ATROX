import Foundation

public enum AccountError: Error, Equatable, Sendable {
    case failed
}

/// Account-level server operations: data export and account deletion.
/// Production: `SupabaseAccountService` (Edge Functions `export-data` / `delete-account`, P045); tests and builds
/// without a server use `FakeAccountService`.
public protocol AccountService: Sendable {
    /// Prepares a copy of the user's data and returns a file the user can share.
    func exportData(userId: UUID) async throws -> URL
    /// Deletes the account and all of its server-side data.
    func deleteAccount(userId: UUID) async throws
}

/// In-memory stand-in: writes a small placeholder JSON for the export and records deletions.
public actor FakeAccountService: AccountService {
    public private(set) var exportedUsers: [UUID] = []
    public private(set) var deletedUsers: [UUID] = []
    private var shouldFail: Bool
    private let delay: Duration
    private let directory: URL

    public init(shouldFail: Bool = false, delay: Duration = .zero, directory: URL = FileManager.default.temporaryDirectory) {
        self.shouldFail = shouldFail
        self.delay = delay
        self.directory = directory
    }

    public func setShouldFail(_ value: Bool) { shouldFail = value }

    public func exportData(userId: UUID) async throws -> URL {
        try await simulateLatency()
        let url = directory.appendingPathComponent("atrox-export-\(userId.uuidString.prefix(8)).json")
        let body = #"{"note":"placeholder export (no server configured)","user_id":"\#(userId.uuidString)"}"#
        try Data(body.utf8).write(to: url, options: .atomic)
        exportedUsers.append(userId)
        return url
    }

    public func deleteAccount(userId: UUID) async throws {
        try await simulateLatency()
        deletedUsers.append(userId)
    }

    private func simulateLatency() async throws {
        if delay > .zero { try await Task.sleep(for: delay) }
        if shouldFail { throw AccountError.failed }
    }
}
