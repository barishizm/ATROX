import Foundation

/// One row of `public.model_versions` (P063).
public struct ModelVersionRecord: Sendable, Equatable, Codable {
    public var version: String
    public var schemaVersion: Int
    public var minAppVersion: String
    /// Folder inside the `model-bundles` bucket holding manifest.json, manifest.sig and the listed files.
    public var storagePath: String
    public var manifestSha256: String
    public var isActive: Bool
    public var rolloutPercent: Int

    public init(
        version: String, schemaVersion: Int, minAppVersion: String, storagePath: String, manifestSha256: String,
        isActive: Bool, rolloutPercent: Int
    ) {
        self.version = version
        self.schemaVersion = schemaVersion
        self.minAppVersion = minAppVersion
        self.storagePath = storagePath
        self.manifestSha256 = manifestSha256
        self.isActive = isActive
        self.rolloutPercent = rolloutPercent
    }

    enum CodingKeys: String, CodingKey {
        case version, schemaVersion = "schema_version", minAppVersion = "min_app_version", storagePath = "storage_path"
        case manifestSha256 = "manifest_sha256", isActive = "is_active", rolloutPercent = "rollout_percent"
    }
}

/// Where versions and bundle files come from (Supabase in the app, a fake in tests).
public protocol ModelVersionSource: Sendable {
    /// Active rows of `model_versions`.
    func activeVersions() async throws -> [ModelVersionRecord]
    /// Bytes of `<storagePath>/<file>` in the `model-bundles` bucket.
    func download(_ path: String) async throws -> Data
}

/// Keeps the on-device model bundle current (docs/03-ML-MODEL.md §11 "Güncelleme"): checks on launch and at most once a
/// day, installs a newer compatible active version (download → signature/digests → smoke test → atomic activation),
/// follows server rollbacks (`is_active = false`) and never leaves the device without a working bundle: any failure
/// keeps the current one, and the embedded bundle is the last resort.
public actor ModelUpdater {
    public enum Outcome: Sendable, Equatable {
        case notDue
        case upToDate
        case updated(from: String, to: String)
        case rolledBack(from: String, to: String)
        case failed(String)
    }

    /// A model version change the user has not been told about yet (P064 recomputes scores and explains it once).
    public struct Change: Codable, Sendable, Equatable {
        public let from: String
        public let to: String
    }

    struct State: Codable, Equatable {
        var active: String?
        var lastCheck: Date?
        var pendingChange: Change?
    }

    private let source: any ModelVersionSource
    private let directory: URL
    private let appVersion: String
    private let deviceId: String
    private let checkInterval: TimeInterval
    private let publicKeyBase64: String
    private let now: @Sendable () -> Date
    private var state: State

    public init(
        source: any ModelVersionSource, directory: URL, appVersion: String, deviceId: String,
        checkInterval: TimeInterval = 24 * 60 * 60, publicKeyBase64: String = ModelBundle.trustedPublicKeyBase64,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.directory = directory
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.checkInterval = checkInterval
        self.publicKeyBase64 = publicKeyBase64
        self.now = now
        let stateURL = directory.appendingPathComponent("state.json")
        self.state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
    }

    // MARK: Active bundle

    private func bundleDirectory(_ version: String) -> URL {
        directory.appendingPathComponent("bundles").appendingPathComponent(version)
    }

    private func loadInstalled(_ version: String) -> ModelBundle? {
        try? ModelBundle.load(from: bundleDirectory(version), appVersion: appVersion, publicKeyBase64: publicKeyBase64)
    }

    /// The bundle to score with: the activated download if it still verifies, else the embedded bundle.
    public func currentBundle() throws(StrengthModelError) -> ModelBundle {
        if let active = state.active, let bundle = loadInstalled(active) { return bundle }
        return try ModelBundle.embedded(appVersion: appVersion)
    }

    public var activeVersion: String? { state.active }

    /// When the version list was last fetched successfully (the "how it works" screen shows it).
    public var lastCheckedAt: Date? { state.lastCheck }

    public func pendingChange() -> Change? { state.pendingChange }

    public func acknowledgeChange() {
        state.pendingChange = nil
        try? save()
    }

    // MARK: Checking

    /// On launch / foreground: checks only when the last successful check is older than the interval.
    public func checkIfDue() async -> Outcome {
        if let last = state.lastCheck, now().timeIntervalSince(last) < checkInterval { return .notDue }
        return await check()
    }

    public func check() async -> Outcome {
        let records: [ModelVersionRecord]
        do {
            records = try await source.activeVersions()
        } catch {
            return .failed("version list: \(error)")
        }
        let embeddedVersion = (try? ModelBundle.embedded(appVersion: appVersion).manifest.version) ?? "0.0.0"
        let current = state.active.flatMap { loadInstalled($0) != nil ? $0 : nil }
        let currentVersion = current ?? embeddedVersion
        let eligible = records.filter(isEligible)
        let target = eligible.max { semver($0.version) < semver($1.version) }

        var desired: ModelVersionRecord?
        if let current, !eligible.contains(where: { $0.version == current }) {
            // Server rolled the active version back: newest remaining eligible version, else the embedded bundle.
            desired = target.flatMap { semver($0.version) > semver(embeddedVersion) ? $0 : nil }
        } else if let target, semver(target.version) > semver(currentVersion) {
            desired = target
        } else {
            desired = current.flatMap { version in eligible.first { $0.version == version } }
        }

        let newVersion = desired?.version ?? embeddedVersion
        if desired?.version == current {
            state.lastCheck = now()
            try? save()
            return .upToDate
        }
        if let desired, loadInstalled(desired.version) == nil {
            do {
                try await install(desired)
            } catch {
                return .failed("\(desired.version): \(error)")
            }
        }
        state.active = desired?.version
        state.lastCheck = now()
        if newVersion != currentVersion { state.pendingChange = Change(from: currentVersion, to: newVersion) }
        do {
            try save()
        } catch {
            return .failed("state: \(error)")
        }
        if newVersion == currentVersion { return .upToDate }
        return semver(newVersion) > semver(currentVersion)
            ? .updated(from: currentVersion, to: newVersion) : .rolledBack(from: currentVersion, to: newVersion)
    }

    private func isEligible(_ record: ModelVersionRecord) -> Bool {
        guard record.isActive, record.schemaVersion == ModelParams.supportedSchemaVersion,
              SemanticVersion(record.version) != nil,
              let minApp = SemanticVersion(record.minAppVersion), let app = SemanticVersion(appVersion), app >= minApp else {
            return false
        }
        return Self.rolloutBucket(deviceId: deviceId, version: record.version) < record.rolloutPercent
    }

    private func semver(_ text: String) -> SemanticVersion {
        SemanticVersion(text) ?? .zero
    }

    /// Stable 0–99 bucket per device and version (FNV-1a 64), so each release rolls out to its own cohort.
    public static func rolloutBucket(deviceId: String, version: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(deviceId)|\(version)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % 100)
    }

    // MARK: Install

    private func install(_ record: ModelVersionRecord) async throws {
        let fm = FileManager.default
        let staging = directory.appendingPathComponent("staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let manifestData = try await source.download("\(record.storagePath)/manifest.json")
        guard try ModelBundle.sha256Hex(manifestData) == record.manifestSha256.lowercased() else {
            throw StrengthModelError.bundle("manifest digest does not match model_versions")
        }
        let manifest: ModelBundle.Manifest = try decodeJSON(manifestData)
        guard manifest.version == record.version else { throw StrengthModelError.bundle("manifest version mismatch") }
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
        try await source.download("\(record.storagePath)/manifest.sig").write(to: staging.appendingPathComponent("manifest.sig"))
        for name in manifest.files.keys.sorted() {
            guard !name.contains("/"), !name.hasPrefix(".") else { throw StrengthModelError.bundle("invalid file name \(name)") }
            try await source.download("\(record.storagePath)/\(name)").write(to: staging.appendingPathComponent(name))
        }
        let bundle = try ModelBundle.load(from: staging, appVersion: appVersion, publicKeyBase64: publicKeyBase64)
        let smoke = try Data(contentsOf: staging.appendingPathComponent("smoke.json"))
        try ModelSmokeTest.run(bundle.model, data: smoke)

        let destination = bundleDirectory(record.version)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }
}

/// Runs a bundle's `smoke.json` (a subset of the end-to-end golden vectors) against its own model.
public enum ModelSmokeTest {
    struct Case: Decodable {
        struct User: Decodable {
            let sex: ModelSex?
            let age: Double
            let bodyweightKg: Double
        }

        struct LoggedSet: Decodable {
            let day: Int
            let weightKg: Double
            let reps: Int
            let rir: Double?
            let isWarmup: Bool
            let confirmed: Bool
        }

        struct Exercise: Decodable {
            let exerciseId: String
            let sets: [LoggedSet]
        }

        struct Input: Decodable {
            let user: User
            let asOfDay: Int
            let population: ReferencePopulation
            let exercises: [Exercise]
        }

        struct Score: Decodable {
            let score: Double
            let z: Double
        }

        struct Expected: Decodable {
            let exercises: [String: Score?]
        }

        let input: Input
        let expected: Expected
    }

    struct File: Decodable {
        let tolerance: Double
        let cases: [Case]
    }

    public static func run(_ model: StrengthModel, data: Data) throws(StrengthModelError) {
        let file: File = try decodeJSON(data)
        guard !file.cases.isEmpty else { throw .bundle("smoke test has no cases") }
        for (idx, smoke) in file.cases.enumerated() {
            let input = smoke.input
            let user = ScoringUser(sex: input.user.sex, age: input.user.age, bodyweightKg: input.user.bodyweightKg)
            for ex in input.exercises {
                let tax = try model.exercise(ex.exerciseId)
                let sets = ex.sets.map {
                    ScoringSet(day: $0.day, weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir, isWarmup: $0.isWarmup, confirmed: $0.confirmed)
                }
                let result: ExerciseScore?
                if tax.scoringType == "reps_only" {
                    let none = CurrentStrength(e1rmKg: nil, confidence: .low, stale: false, sessionsInWindow: 0)
                    let reps = Double(sets.map(\.reps).max() ?? 0)
                    result = try model.exerciseScore(tax, strength: none, user: user, population: input.population, reps: reps)
                } else {
                    let strength = try model.currentStrength(tax, sets: sets, user: user, asOfDay: input.asOfDay)
                    result = try model.exerciseScore(tax, strength: strength, user: user, population: input.population)
                }
                let expected = smoke.expected.exercises[ex.exerciseId] ?? nil
                let matches = switch (result, expected) {
                case (nil, nil): true
                case let (got?, want?): abs(got.score - want.score) <= file.tolerance && abs(got.z - want.z) <= file.tolerance
                default: false
                }
                guard matches else { throw .bundle("smoke test case \(idx) \(ex.exerciseId) does not match") }
            }
        }
    }
}
