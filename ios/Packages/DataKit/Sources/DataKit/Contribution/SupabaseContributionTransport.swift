import Foundation

public enum ContributionError: Error, Sendable, Equatable {
    case unauthorized, rejected, failed
}

/// `contribute` Edge Function client. The session token only serves the server's rate limit; the body carries no user id.
public struct SupabaseContributionTransport: ContributionTransport {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: SupabaseRemoteStore.AccessToken
    private let fetch: Fetch

    public init(configuration: SupabaseConfiguration, accessToken: @escaping SupabaseRemoteStore.AccessToken, session: URLSession = .shared) {
        self.init(baseURL: configuration.url, anonKey: configuration.anonKey, accessToken: accessToken) { try await session.data(for: $0) }
    }

    init(baseURL: URL, anonKey: String, accessToken: @escaping SupabaseRemoteStore.AccessToken, fetch: @escaping Fetch) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.fetch = fetch
    }

    public func send(_ payload: ContributionPayload) async throws {
        try await perform("POST", body: try JSONEncoder().encode(payload))
    }

    public func delete(contributionKey: UUID) async throws {
        try await perform("DELETE", body: try JSONEncoder().encode(["contribution_key": contributionKey.uuidString.lowercased()]))
    }

    private func perform(_ method: String, body: Data) async throws {
        guard let token = await accessToken() else { throw ContributionError.unauthorized }
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/contribute"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await fetch(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ContributionError.failed }
        switch status {
        case 200..<300: return
        case 401: throw ContributionError.unauthorized
        case 400: throw ContributionError.rejected
        default: throw ContributionError.failed
        }
    }
}
