import Foundation
import Testing

@testable import DataKit

struct NonceAndConfigTests {
    @Test func nonceIsRandomWithRequestedLength() {
        let first = Nonce.random(length: 32), second = Nonce.random(length: 32)
        #expect(first.raw.count == 32)
        #expect(first != second)
        #expect(Nonce.random(length: 5).raw.count == 5)
    }

    @Test func sha256KnownVector() {
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Nonce(raw: "abc").hashed == Nonce.sha256("abc"))
    }

    @Test func configFromInfoDictionary() {
        let good: [String: Any] = ["SupabaseURL": "http://127.0.0.1:54321", "SupabaseAnonKey": "key"]
        let config = SupabaseConfiguration(infoDictionary: good, urlScheme: "atrox")
        #expect(config?.url.absoluteString == "http://127.0.0.1:54321")
        #expect(config?.redirectURL?.absoluteString == "atrox://auth-callback")
    }

    @Test func placeholderOrMissingConfigIsRejected() {
        #expect(SupabaseConfiguration(infoDictionary: [:]) == nil)
        #expect(SupabaseConfiguration(infoDictionary: ["SupabaseURL": "https://YOUR-PROJECT-REF.supabase.co", "SupabaseAnonKey": "k"]) == nil)
        #expect(SupabaseConfiguration(infoDictionary: ["SupabaseURL": "http://127.0.0.1:54321", "SupabaseAnonKey": "YOUR_SUPABASE_ANON_KEY"]) == nil)
        #expect(SupabaseConfiguration(infoDictionary: ["SupabaseURL": "not a url", "SupabaseAnonKey": "k"]) == nil)
    }
}
