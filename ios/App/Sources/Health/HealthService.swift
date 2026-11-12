import DataKit
import Foundation

/// What Apple Health knows about the user's body. Every field is optional: the user may have shared only some of them.
struct HealthBodyProfile: Sendable, Equatable {
    var heightCm: Double?
    var weightKg: Double?
    var birthDate: Date?
    /// nil when Health has no value (or it is "other"/"not set").
    var sex: Sex?

    var isEmpty: Bool { heightCm == nil && weightKg == nil && birthDate == nil && sex == nil }
}

/// One body-mass reading from Health.
struct HealthWeightSample: Sendable, Equatable {
    let date: Date
    let weightKg: Double
    /// Written by this app earlier; never imported back (it already exists locally).
    let isFromThisApp: Bool
}

/// The app's door to Apple Health (P023). Health data stays on the device: it is never sent to the coach or to the
/// anonymous contribution as it is (docs/02-MIMARI.md §3.4).
///
/// No method throws: a missing HealthKit, a denied permission or a failed query all end as "no data", so callers
/// fall back to manual entry without special cases. (Health hides whether *read* access was granted.)
protocol HealthService: Sendable {
    /// False on devices without Health (and in tests that stub it out).
    var isAvailable: Bool { get }
    /// Shows the system permission sheet if the user has not decided yet. Call it only after a button press.
    /// Returns false when Health is unavailable or the request failed; says nothing about what was granted.
    func requestAuthorization() async -> Bool
    /// Whether this app may write body weight. Never prompts.
    func canWriteWeight() async -> Bool
    func bodyProfile() async -> HealthBodyProfile
    /// Body-mass readings from `since` on, in any order.
    func weightSamples(since: Date) async -> [HealthWeightSample]
    @discardableResult
    func saveWeight(kilograms: Double, date: Date) async -> Bool
}

/// Used where Health does not exist: every button that needs it stays hidden.
struct UnavailableHealthService: HealthService {
    var isAvailable: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func canWriteWeight() async -> Bool { false }
    func bodyProfile() async -> HealthBodyProfile { HealthBodyProfile() }
    func weightSamples(since: Date) async -> [HealthWeightSample] { [] }
    func saveWeight(kilograms: Double, date: Date) async -> Bool { false }
}

/// In-memory Health for tests and UI tests (`-uitest-fake-health`).
actor FakeHealthService: HealthService {
    nonisolated let isAvailable: Bool
    private var authorizationGranted: Bool
    private var profile: HealthBodyProfile
    private var samples: [HealthWeightSample]
    private(set) var saved: [HealthWeightSample] = []
    private(set) var authorizationRequests = 0

    init(
        isAvailable: Bool = true, authorizationGranted: Bool = true,
        profile: HealthBodyProfile = HealthBodyProfile(), samples: [HealthWeightSample] = []
    ) {
        self.isAvailable = isAvailable
        self.authorizationGranted = authorizationGranted
        self.profile = profile
        self.samples = samples
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return isAvailable
    }

    func canWriteWeight() async -> Bool { isAvailable && authorizationGranted }

    func bodyProfile() async -> HealthBodyProfile { authorizationGranted ? profile : HealthBodyProfile() }

    func weightSamples(since: Date) async -> [HealthWeightSample] {
        guard authorizationGranted else { return [] }
        return samples.filter { $0.date >= since }
    }

    func saveWeight(kilograms: Double, date: Date) async -> Bool {
        guard await canWriteWeight() else { return false }
        let sample = HealthWeightSample(date: date, weightKg: kilograms, isFromThisApp: true)
        saved.append(sample)
        samples.append(sample)
        return true
    }
}
