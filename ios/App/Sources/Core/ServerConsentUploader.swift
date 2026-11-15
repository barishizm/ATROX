import Foundation

/// Writes one AI-sharing consent row to the server's append-only `consents` table (RLS: the caller's own rows only).
/// The coach endpoint decides on that table, and consents are not part of the sync engine yet.
struct ServerConsentUploader: Sendable {
    let baseURL: URL
    let anonKey: String
    let accessToken: @Sendable () async -> String?
    var session: URLSession = .shared

    func uploadAISharing(userId: UUID, version: String) async -> Bool {
        guard let token = await accessToken() else { return false }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/consents"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "user_id": userId.uuidString.lowercased(),
            "kind": "ai_sharing", "version": version, "granted": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
