import CryptoKit
import Foundation
import Security

/// Nonce pair for Sign in with Apple: Apple receives the SHA-256 hash, Supabase the raw value.
public struct Nonce: Sendable, Equatable {
    public let raw: String
    public var hashed: String { Nonce.sha256(raw) }

    public init(raw: String) { self.raw = raw }

    public static func random(length: Int = 32) -> Nonce {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "Unable to generate nonce")
            for byte in bytes where result.count < length && byte < 248 {  // 248 = 4 * 62 → no modulo bias
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return Nonce(raw: result)
    }

    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
