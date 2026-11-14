import Foundation
import Testing
@testable import CoachKit

@Suite struct CoachErrorTests {
    private func body(_ code: String, details: String = "null") -> Data {
        Data(#"{"error":{"code":"\#(code)","message":"m","details":\#(details)}}"#.utf8)
    }

    @Test func consentRequiredCarriesTheVersion() {
        let error = CoachError.from(status: 403, body: body("consent_required", details: #"{"required_version":"2026-11"}"#))
        #expect(error == .consentRequired(requiredVersion: "2026-11"))
    }

    @Test func quotaAndRateLimitCarryResetTimes() {
        let details = #"{"reset_at":"2026-11-15T00:00:00.000Z","upgrade_available":true}"#
        guard case .quotaExceeded(let reset, let upgrade) = CoachError.from(status: 429, body: body("quota_exceeded", details: details)) else {
            Issue.record("expected quotaExceeded")
            return
        }
        #expect(reset != nil && upgrade)
        guard case .rateLimited(let retry) = CoachError.from(status: 429, body: body("rate_limited", details: details)) else {
            Issue.record("expected rateLimited")
            return
        }
        #expect(retry != nil)
    }

    @Test func otherCodesMap() {
        #expect(CoachError.from(status: 400, body: body("duplicate_message")) == .duplicateMessage)
        #expect(CoachError.from(status: 503, body: body("coach_unavailable")) == .unavailable)
        #expect(CoachError.from(status: 401, body: Data()) == .unauthorized)
        #expect(CoachError.from(status: 500, body: Data("<html>".utf8)) == .server(code: "http_500", message: ""))
    }

    @Test func networkFailuresMap() {
        #expect(CoachError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(CoachError.from(URLError(.networkConnectionLost)) == .offline)
        #expect(CoachError.from(URLError(.timedOut)) == .timeout)
        #expect(CoachError.from(URLError(.cancelled)) == .cancelled)
        #expect(CoachError.from(CancellationError()) == .cancelled)
    }

    @Test func onlyTransientErrorsAreRetryable() {
        #expect(CoachError.offline.isRetryable && !CoachError.quotaExceeded(resetAt: nil, upgradeAvailable: false).isRetryable)
        #expect(!CoachError.consentRequired(requiredVersion: nil).isRetryable)
    }
}
