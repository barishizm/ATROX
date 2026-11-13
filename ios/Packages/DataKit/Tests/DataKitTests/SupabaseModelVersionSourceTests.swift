@testable import DataKit
import Foundation
import StrengthKit
import Testing

@Suite struct SupabaseModelVersionSourceTests {
    @Test func readsActiveRowsAndDownloadsFromThePublicBucket() async throws {
        let base = try #require(URL(string: "https://example.supabase.co"))
        let row = #"[{"version":"1.1.0","schema_version":1,"min_app_version":"1.0.0","storage_path":"v1.1.0","#
            + #""manifest_sha256":"\#(String(repeating: "a", count: 64))","is_active":true,"rollout_percent":25}]"#
        let source = SupabaseModelVersionSource(baseURL: base, anonKey: "anon") { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
            let body = url.path.hasPrefix("/rest/v1/model_versions") ? Data(row.utf8) : Data("file".utf8)
            if url.path.hasPrefix("/rest/") { #expect(url.query?.contains("is_active=eq.true") == true) }
            return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)  // swiftlint:disable:this force_unwrapping
        }
        let records = try await source.activeVersions()
        #expect(records == [ModelVersionRecord(
            version: "1.1.0", schemaVersion: 1, minAppVersion: "1.0.0", storagePath: "v1.1.0",
            manifestSha256: String(repeating: "a", count: 64), isActive: true, rolloutPercent: 25
        )])
        #expect(try await source.download("v1.1.0/params.json") == Data("file".utf8))
    }

    @Test func httpErrorsThrow() async throws {
        let base = try #require(URL(string: "https://example.supabase.co"))
        let source = SupabaseModelVersionSource(baseURL: base, anonKey: "anon") { request in
            (Data(), HTTPURLResponse(url: try #require(request.url), statusCode: 404, httpVersion: nil, headerFields: nil)!)  // swiftlint:disable:this force_unwrapping
        }
        await #expect(throws: URLError.self) { try await source.download("v9/manifest.json") }
    }
}
