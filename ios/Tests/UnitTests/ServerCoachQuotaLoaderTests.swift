import Foundation
import Testing

@testable import ATROX

struct ServerCoachQuotaLoaderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func onlyAnActiveUnexpiredProRowGrantsPro() {
        #expect(ServerCoachQuotaLoader.grantsPro(tier: "pro", status: "active", expiresAt: nil, now: now))
        #expect(ServerCoachQuotaLoader.grantsPro(tier: "pro", status: "grace_period", expiresAt: now.addingTimeInterval(60), now: now))
        #expect(!ServerCoachQuotaLoader.grantsPro(tier: "pro", status: "refunded", expiresAt: now.addingTimeInterval(60), now: now))
        #expect(!ServerCoachQuotaLoader.grantsPro(tier: "pro", status: "revoked", expiresAt: nil, now: now))
        #expect(!ServerCoachQuotaLoader.grantsPro(tier: "pro", status: "active", expiresAt: now.addingTimeInterval(-60), now: now))
        #expect(!ServerCoachQuotaLoader.grantsPro(tier: "free", status: "active", expiresAt: nil, now: now))
    }
}
