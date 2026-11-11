import DataKit
import GoogleSignIn
import UIKit

/// Google Sign-In (GoogleSignIn SDK). Client IDs come from Info.plist (`GIDClientID`, `GIDServerClientID`),
/// which are filled from xcconfig. The raw nonce is bound to the ID token and verified by Supabase.
@MainActor
struct GoogleIDTokenProvider: IDTokenProvider {
    nonisolated func credential() async throws -> IDTokenCredential {
        try await signIn()
    }

    private func signIn() async throws -> IDTokenCredential {
        guard let presenter = UIApplication.shared.keyWindowForAuth?.rootViewController?.topMostPresented else {
            throw AuthError.providerUnavailable
        }
        let nonce = Nonce.random()
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce.hashed
            )
            guard let idToken = result.user.idToken?.tokenString else { throw AuthError.providerUnavailable }
            return IDTokenCredential(
                idToken: idToken, accessToken: result.user.accessToken.tokenString, nonce: nonce.raw
            )
        } catch {
            throw AuthError.map(error)
        }
    }
}

private extension UIViewController {
    var topMostPresented: UIViewController {
        presentedViewController?.topMostPresented ?? self
    }
}
