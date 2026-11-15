import Foundation

/// Where consent rows go. The server's `consents` table is insert-only, so a row is written once and never updated.
public protocol ConsentRemote: Sendable {
    func insert(_ consent: ConsentSnapshot) async throws
}

/// Pushes the device's consent rows to the server (D129). The coach endpoint decides on the latest server row per kind,
/// so a withdrawal must reach the server as well as a grant; the legal record also lives there.
public actor ConsentPusher {
    private let repository: any ConsentRepository
    private let remote: any ConsentRemote

    public init(repository: any ConsentRepository, remote: any ConsentRemote) {
        self.repository = repository
        self.remote = remote
    }

    /// Sends every unsynced row, oldest first, and marks each one after the server accepted it. Stops at the first
    /// failure (order matters: the latest row wins) and returns whether nothing is left to send.
    @discardableResult
    public func push(userId: UUID) async -> Bool {
        guard let rows = try? await repository.unsynced(userId: userId) else { return false }
        for row in rows {
            do {
                try await remote.insert(row)
                try await repository.markSynced(ids: [row.id])
            } catch {
                return false
            }
        }
        return true
    }
}

/// PostgREST insert with `on_conflict=id` + ignore-duplicates, so a retry after a lost response is harmless.
public struct SupabaseConsentRemote: ConsentRemote {
    public typealias AccessToken = @Sendable () async -> String?

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: AccessToken
    private let session: URLSession

    public init(configuration: SupabaseConfiguration, accessToken: @escaping AccessToken, session: URLSession = .shared) {
        self.baseURL = configuration.url
        self.anonKey = configuration.anonKey
        self.accessToken = accessToken
        self.session = session
    }

    public func insert(_ consent: ConsentSnapshot) async throws {
        guard let token = await accessToken() else { throw URLError(.userAuthenticationRequired) }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/consents"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "id": consent.id.uuidString.lowercased(), "user_id": consent.userId.uuidString.lowercased(),
            "kind": consent.kind.rawValue, "version": consent.version, "granted": consent.granted,
            "created_at": ISO8601DateFormatter().string(from: consent.createdAt)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}
