import CryptoKit
import Foundation

/// The `appAccountToken` attached to every purchase (P089): a UUID derived from the user's Supabase id with a fixed
/// namespace (UUID version 5), so Apple's transactions carry a stable link to the account without exposing the id.
/// The server derives the same value (`appstore-notifications`, P090) to match a transaction to its user.
enum AppAccountToken {
    /// Fixed namespace; changing it would orphan every existing subscription. Same constant on the server.
    static let namespace = UUID(uuidString: "6f1c7a52-3b0e-5d44-9a1e-0a7c2e9b41d8")!

    static func make(for userId: UUID) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(userId.uuidString.lowercased().utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}
