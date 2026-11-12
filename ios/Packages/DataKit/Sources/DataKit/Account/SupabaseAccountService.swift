import Foundation

/// `AccountService` over the `export-data` and `delete-account` Edge Functions (P045).
public struct SupabaseAccountService: AccountService {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let anonKey: String
    private let accessToken: SupabaseRemoteStore.AccessToken
    /// A fresh Sign in with Apple authorization code for Apple users (so the server can revoke their tokens); nil for
    /// other users or when the user cancels the Apple sheet.
    private let appleAuthorizationCode: @Sendable () async -> String?
    private let directory: URL
    private let fetch: Fetch

    public init(
        configuration: SupabaseConfiguration, accessToken: @escaping SupabaseRemoteStore.AccessToken,
        appleAuthorizationCode: @escaping @Sendable () async -> String? = { nil },
        directory: URL = FileManager.default.temporaryDirectory, session: URLSession = .shared
    ) {
        self.init(
            baseURL: configuration.url, anonKey: configuration.anonKey, accessToken: accessToken,
            appleAuthorizationCode: appleAuthorizationCode, directory: directory
        ) { try await session.data(for: $0) }
    }

    init(
        baseURL: URL, anonKey: String, accessToken: @escaping SupabaseRemoteStore.AccessToken,
        appleAuthorizationCode: @escaping @Sendable () async -> String?, directory: URL, fetch: @escaping Fetch
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.appleAuthorizationCode = appleAuthorizationCode
        self.directory = directory
        self.fetch = fetch
    }

    public func exportData(userId: UUID) async throws -> URL {
        let data = try await call("export-data", body: [:])
        // Only hand out a file that really is JSON.
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw AccountError.failed }
        let stamp = SyncTime.day(Date())
        let url = directory.appendingPathComponent("atrox-export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    public func deleteAccount(userId: UUID) async throws {
        var body: [String: String] = [:]
        if let code = await appleAuthorizationCode() { body["apple_authorization_code"] = code }
        _ = try await call("delete-account", body: body)
    }

    private func call(_ function: String, body: [String: String]) async throws -> Data {
        guard let token = await accessToken() else { throw AccountError.failed }
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AccountError.failed
        }
        return data
    }
}
