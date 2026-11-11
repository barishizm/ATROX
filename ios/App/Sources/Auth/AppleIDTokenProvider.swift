import AuthenticationServices
import DataKit
import UIKit

/// Native Sign in with Apple: ASAuthorization with a hashed nonce → identity token + raw nonce for Supabase.
@MainActor
final class AppleIDTokenProvider: NSObject, IDTokenProvider {
    private var continuation: CheckedContinuation<IDTokenCredential, any Error>?
    private var nonce: Nonce?
    private var controller: ASAuthorizationController?

    nonisolated func credential() async throws -> IDTokenCredential {
        try await run()
    }

    private func run() async throws -> IDTokenCredential {
        // A previous attempt that never completed must not leak its continuation.
        finish(.failure(AuthError.cancelled))

        let nonce = Nonce.random()
        self.nonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<IDTokenCredential, any Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        nonce = nil
        pending?.resume(with: result)
    }
}

extension AppleIDTokenProvider: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = apple.identityToken,
            let token = String(data: tokenData, encoding: .utf8),
            let nonce
        else { return finish(.failure(AuthError.providerUnavailable)) }
        finish(.success(IDTokenCredential(idToken: token, nonce: nonce.raw)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(AuthError.map(error)))
    }
}

extension AppleIDTokenProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = UIApplication.shared.keyWindowForAuth { return window }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { preconditionFailure("No window scene for Sign in with Apple") }
        return UIWindow(windowScene: scene)
    }
}

extension UIApplication {
    /// The foreground key window, used as the anchor/presenter for provider sheets.
    var keyWindowForAuth: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
