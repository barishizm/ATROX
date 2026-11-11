import Foundation
import Supabase
import Testing

@testable import DataKit

private typealias AuthError = DataKit.AuthError

struct AuthErrorMappingTests {
    private func api(_ code: ErrorCode, status: Int = 400) -> Supabase.AuthError {
        .api(
            message: "x", errorCode: code, underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "http://localhost")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }

    @Test func networkFailuresAreOffline() {
        #expect(AuthError.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(AuthError.map(URLError(.timedOut)) == .offline)
    }

    @Test func cancellation() {
        #expect(AuthError.map(CancellationError()) == .cancelled)
        #expect(AuthError.map(URLError(.cancelled)) == .cancelled)
        #expect(AuthError.map(NSError(domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1001)) == .cancelled)
        #expect(AuthError.map(NSError(domain: "com.google.GIDSignIn", code: -5)) == .cancelled)
    }

    @Test func apiCodes() {
        #expect(AuthError.map(api(.invalidCredentials)) == .invalidCredentials)
        #expect(AuthError.map(api(.emailNotConfirmed)) == .emailNotConfirmed)
        #expect(AuthError.map(api(.userAlreadyExists)) == .emailAlreadyRegistered)
        #expect(AuthError.map(api(.emailExists)) == .emailAlreadyRegistered)
        #expect(AuthError.map(api(.weakPassword)) == .weakPassword)
        #expect(AuthError.map(api(.overRequestRateLimit, status: 429)) == .rateLimited)
        #expect(AuthError.map(api(.unknown, status: 429)) == .rateLimited)
        #expect(AuthError.map(api(.refreshTokenNotFound)) == .sessionExpired)
        #expect(AuthError.map(api(.providerDisabled)) == .providerUnavailable)
        #expect(AuthError.map(api(.unexpectedFailure, status: 500)) == .unknown)
    }

    @Test func sdkSpecificCases() {
        #expect(AuthError.map(Supabase.AuthError.sessionMissing) == .sessionExpired)
        #expect(AuthError.map(Supabase.AuthError.weakPassword(message: "x", reasons: ["length"])) == .weakPassword)
    }

    @Test func existingAuthErrorPassesThrough() {
        #expect(AuthError.map(AuthError.rateLimited) == .rateLimited)
    }

    @Test func unknownErrors() {
        struct Boom: Error {}
        #expect(AuthError.map(Boom()) == .unknown)
    }

    @Test func everyCaseHasALocalizedMessage() {
        let all: [AuthError] = [
            .offline, .invalidCredentials, .emailNotConfirmed, .emailAlreadyRegistered, .weakPassword,
            .rateLimited, .cancelled, .sessionExpired, .providerUnavailable, .notConfigured, .unknown,
        ]
        for error in all {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            #expect(!message.hasPrefix("auth.error."), "missing translation for \(error)")
        }
    }
}
