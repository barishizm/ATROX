import Foundation
import Supabase

/// Connection settings for the Supabase project, read from the app's Info.plist
/// (values originate in the xcconfig files; see docs/KURULUM.md).
public struct SupabaseConfiguration: Sendable, Equatable {
    public let url: URL
    public let anonKey: String
    /// Deep link that email confirmation / password-reset links return to, e.g. `atrox://auth-callback`.
    public let redirectURL: URL?

    public init(url: URL, anonKey: String, redirectURL: URL? = nil) {
        self.url = url
        self.anonKey = anonKey
        self.redirectURL = redirectURL
    }

    /// Reads `SupabaseURL`, `SupabaseAnonKey` and the `APP_URL_SCHEME`-based redirect from an Info.plist
    /// dictionary. Returns nil when a value is missing or still a template placeholder.
    public init?(infoDictionary: [String: Any], urlScheme: String? = nil) {
        guard
            let urlString = infoDictionary["SupabaseURL"] as? String,
            let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true, url.host != nil,
            let key = infoDictionary["SupabaseAnonKey"] as? String,
            !key.isEmpty, !key.hasPrefix("YOUR_"), !url.absoluteString.contains("YOUR-PROJECT")
        else { return nil }
        self.init(
            url: url,
            anonKey: key,
            redirectURL: urlScheme.flatMap { $0.isEmpty ? nil : URL(string: "\($0)://auth-callback") }
        )
    }

    /// Builds the client. Session persistence uses the SDK default (Keychain on Apple platforms).
    public func makeClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: redirectURL, flowType: .pkce)
            )
        )
    }
}
