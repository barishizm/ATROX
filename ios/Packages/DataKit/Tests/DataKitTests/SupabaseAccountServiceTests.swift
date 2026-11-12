@testable import DataKit
import Foundation
import Testing

@Suite("SupabaseAccountService (P045)")
struct SupabaseAccountServiceTests {
    private func service(_ stub: StubHTTP, appleCode: String? = nil) -> SupabaseAccountService {
        SupabaseAccountService(
            baseURL: URL(string: "http://127.0.0.1:54321")!, anonKey: "anon", accessToken: { "jwt" },
            appleAuthorizationCode: { appleCode }, directory: FileManager.default.temporaryDirectory, fetch: stub.fetch
        )
    }

    @Test func exportWritesTheServersJSONToAFile() async throws {
        let stub = StubHTTP([(200, #"{"format_version":1,"tables":{"workouts":[]}}"#)])
        let url = try await service(stub).exportData(userId: testUser)

        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:54321/functions/v1/export-data")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(saved?["format_version"] as? Int == 1)
        #expect(url.lastPathComponent.hasPrefix("atrox-export-"))
    }

    @Test func exportRejectsAnAnswerThatIsNotJSON() async {
        let stub = StubHTTP([(200, "<html>")])
        await #expect(throws: AccountError.failed) { try await service(stub).exportData(userId: testUser) }
    }

    @Test func deleteSendsTheAppleCodeWhenThereIsOne() async throws {
        let stub = StubHTTP([(200, #"{"deleted":true}"#), (200, #"{"deleted":true}"#)])
        try await service(stub, appleCode: "c0de").deleteAccount(userId: testUser)
        try await service(stub).deleteAccount(userId: testUser)

        let bodies = stub.requests.map { try? JSONSerialization.jsonObject(with: $0.httpBody ?? Data()) as? [String: String] }
        #expect(stub.requests.first?.url?.path == "/functions/v1/delete-account")
        #expect(bodies == [["apple_authorization_code": "c0de"], [:]])
    }

    @Test func serverErrorsFail() async {
        let stub = StubHTTP([(500, #"{"error":"delete_failed"}"#)])
        await #expect(throws: AccountError.failed) { try await service(stub).deleteAccount(userId: testUser) }
    }
}
