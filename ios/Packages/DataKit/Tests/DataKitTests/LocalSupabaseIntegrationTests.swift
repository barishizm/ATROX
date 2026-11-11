import Foundation
import Testing

@testable import DataKit

/// Runs against `supabase start` only when SUPABASE_LOCAL_URL and SUPABASE_LOCAL_ANON_KEY are set, e.g.
///   SUPABASE_LOCAL_URL=http://127.0.0.1:54321 SUPABASE_LOCAL_ANON_KEY=$(supabase status -o env | …) swift test
/// The local auth config allows 2 e-mails/hour (auth.rate_limit.email_sent); this test sends one, so avoid
/// re-running it more than twice an hour (or restart the auth container to reset the counter).
/// Confirmation e-mails are read from Mailpit (SUPABASE_LOCAL_MAILPIT_URL, default http://127.0.0.1:54324).
private let env = ProcessInfo.processInfo.environment

@Suite(.enabled(if: env["SUPABASE_LOCAL_URL"] != nil && env["SUPABASE_LOCAL_ANON_KEY"] != nil))
struct LocalSupabaseIntegrationTests {
    private func makeService() throws -> SupabaseAuthService {
        let config = try #require(SupabaseConfiguration(
            infoDictionary: ["SupabaseURL": env["SUPABASE_LOCAL_URL"]!, "SupabaseAnonKey": env["SUPABASE_LOCAL_ANON_KEY"]!],
            urlScheme: "vesania"
        ))
        return SupabaseAuthService(configuration: config)
    }

    /// Opens the newest confirmation link sent to `email` without following the app deep-link redirect.
    private func confirm(email: String) async throws {
        let mailpit = URL(string: env["SUPABASE_LOCAL_MAILPIT_URL"] ?? "http://127.0.0.1:54324")!
        var link: URL?
        for _ in 0..<20 where link == nil {
            let (listData, _) = try await URLSession.shared.data(from: mailpit.appending(path: "api/v1/search").appending(queryItems: [.init(name: "query", value: "to:\(email)")]))
            let list = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
            if let id = (list?["messages"] as? [[String: Any]])?.first?["ID"] as? String {
                let (msgData, _) = try await URLSession.shared.data(from: mailpit.appending(path: "api/v1/message/\(id)"))
                let msg = try JSONSerialization.jsonObject(with: msgData) as? [String: Any]
                let body = ((msg?["HTML"] as? String) ?? "") + ((msg?["Text"] as? String) ?? "")
                let pattern = #"https?://[^\s"'<>]*auth/v1/verify[^\s"'<>]*"#
                if let range = body.range(of: pattern, options: .regularExpression) {
                    link = URL(string: String(body[range]).replacingOccurrences(of: "&amp;", with: "&"))
                }
            }
            if link == nil { try await Task.sleep(for: .milliseconds(300)) }
        }
        let url = try #require(link, "no confirmation e-mail arrived in Mailpit")
        final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
            func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest: URLRequest) async -> URLRequest? { nil }
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        let (_, response) = try await session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 303 || (response as? HTTPURLResponse)?.statusCode == 302)
    }

    @Test func emailSignUpConfirmSignInRestoreSignOut() async throws {
        let service = try makeService()
        let email = "p015-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let password = "Abcdef12"

        let outcome = try await service.signUp(email: email, password: password, locale: "tr")
        #expect(outcome == .confirmationRequired(email: email))
        await #expect(throws: AuthError.emailNotConfirmed) { try await service.signIn(email: email, password: password) }
        await #expect(throws: AuthError.invalidCredentials) { try await service.signIn(email: email, password: "Wrong1234") }
        await #expect(throws: AuthError.weakPassword) { try await service.signUp(email: "w-\(email)", password: "abcdefgh", locale: nil) }

        try await confirm(email: email)
        let user = try await service.signIn(email: email, password: password)
        #expect(user.email == email)
        #expect(user.isEmailConfirmed)
        #expect(await service.restoreSession() == .signedIn(user))

        // A confirmed address answers a repeat sign-up with an obfuscated user (no identities).
        await #expect(throws: AuthError.emailAlreadyRegistered) { try await service.signUp(email: email, password: password, locale: nil) }

        await service.signOut()
        #expect(await service.restoreSession() == .signedOut)
    }
}
