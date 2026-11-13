// swiftlint:disable identifier_name nesting line_length optional_data_string_conversion
#if canImport(CryptoKit)
import CryptoKit
import Foundation
@testable import StrengthKit
import Testing

/// P063: model updates against a fake `model_versions` + storage. Bundles are re-signed with a throwaway test key.
@Suite struct ModelUpdaterTests {
    final class FakeSource: ModelVersionSource, @unchecked Sendable {
        private let lock = NSLock()
        private var _records: [ModelVersionRecord] = []
        private var _files: [String: Data] = [:]
        var records: [ModelVersionRecord] {
            get { lock.withLock { _records } }
            set { lock.withLock { _records = newValue } }
        }

        func put(_ path: String, _ data: Data) { lock.withLock { _files[path] = data } }

        func activeVersions() async throws -> [ModelVersionRecord] { records.filter(\.isActive) }

        func download(_ path: String) async throws -> Data {
            guard let data = lock.withLock({ _files[path] }) else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }

    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    let source = FakeSource()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("updater-\(UUID().uuidString)")

    func updater(deviceId: String = "device-1", now: @escaping @Sendable () -> Date = { Date() }) -> ModelUpdater {
        ModelUpdater(source: source, directory: dir, appVersion: "1.0.0", deviceId: deviceId, publicKeyBase64: publicKey, now: now)
    }

    /// Publishes the embedded bundle as `version` (optionally edited), signed with `signer`, into the fake storage.
    @discardableResult
    func publish(
        _ version: String, rollout: Int = 100, schema: Int = 1, minApp: String = "1.0.0", signer: Curve25519.Signing.PrivateKey? = nil,
        edit: (inout [String: Data]) -> Void = { _ in }
    ) throws -> ModelVersionRecord {
        let source = try #require(EmbeddedModelBundle.directory)
        var files: [String: Data] = [:]
        for name in ["params.json", "taxonomy.json", "anchor_tables.json", "smoke.json"] {
            files[name] = try Data(contentsOf: source.appendingPathComponent(name))
        }
        edit(&files)
        var manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("manifest.json"))) as? [String: Any]
        )
        manifest["version"] = version
        manifest["files"] = files.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let path = "v\(version)"
        for (name, data) in files { self.source.put("\(path)/\(name)", data) }
        self.source.put("\(path)/manifest.json", manifestData)
        self.source.put("\(path)/manifest.sig", try (signer ?? key).signature(for: manifestData))
        let record = ModelVersionRecord(
            version: version, schemaVersion: schema, minAppVersion: minApp, storagePath: path,
            manifestSha256: SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined(), isActive: true,
            rolloutPercent: rollout
        )
        self.source.records.append(record)
        return record
    }

    @Test func installsNewerVersionAndRecordsTheChange() async throws {
        try publish("1.1.0")
        let updater = updater()
        #expect(await updater.check() == .updated(from: "1.0.0", to: "1.1.0"))
        #expect(try await updater.currentBundle().manifest.version == "1.1.0")
        #expect(await updater.pendingChange() == ModelUpdater.Change(from: "1.0.0", to: "1.1.0"))
        await updater.acknowledgeChange()
        #expect(await updater.pendingChange() == nil)
        #expect(await updater.check() == .upToDate)
        // State survives a restart.
        #expect(try await self.updater().currentBundle().manifest.version == "1.1.0")
    }

    @Test func corruptDownloadKeepsCurrentBundle() async throws {
        let record = try publish("1.1.0")
        source.put("\(record.storagePath)/taxonomy.json", Data("{}".utf8))
        let updater = updater()
        guard case .failed = await updater.check() else { Issue.record("expected failure"); return }
        #expect(try await updater.currentBundle().manifest.version == "1.0.0")
        #expect(await updater.activeVersion == nil)
    }

    @Test func wrongSignatureIsRejected() async throws {
        try publish("1.1.0", signer: Curve25519.Signing.PrivateKey())
        let updater = updater()
        guard case .failed = await updater.check() else { Issue.record("expected failure"); return }
        #expect(try await updater.currentBundle().manifest.version == "1.0.0")
    }

    @Test func manifestDigestMustMatchTheRow() async throws {
        var record = try publish("1.1.0")
        record.manifestSha256 = String(repeating: "0", count: 64)
        source.records = [record]
        guard case .failed = await updater().check() else { Issue.record("expected failure"); return }
    }

    @Test func failingSmokeTestIsRejected() async throws {
        try publish("1.1.0") { files in
            let text = String(decoding: files["params.json"] ?? Data(), as: UTF8.self)
            files["params.json"] = Data(text.replacingOccurrences(of: "\"scoreClip\":[1,99]", with: "\"scoreClip\":[1,50]").utf8)
        }
        let updater = updater()
        guard case let .failed(reason) = await updater.check() else { Issue.record("expected failure"); return }
        #expect(reason.contains("smoke"))
        #expect(await updater.activeVersion == nil)
    }

    @Test func incompatibleVersionsAreIgnored() async throws {
        try publish("2.0.0", schema: 2)
        try publish("1.5.0", minApp: "9.0.0")
        let updater = updater()
        #expect(await updater.check() == .upToDate)
        #expect(await updater.activeVersion == nil)
    }

    @Test func serverRollbackReturnsToPreviousVersion() async throws {
        try publish("1.1.0")
        try publish("1.2.0")
        let updater = updater()
        #expect(await updater.check() == .updated(from: "1.0.0", to: "1.2.0"))
        source.records = source.records.map { var row = $0; row.isActive = row.version != "1.2.0"; return row }
        #expect(await updater.check() == .rolledBack(from: "1.2.0", to: "1.1.0"))
        source.records = source.records.map { var row = $0; row.isActive = false; return row }
        #expect(await updater.check() == .rolledBack(from: "1.1.0", to: "1.0.0"))
        #expect(try await updater.currentBundle().directory.standardizedFileURL == EmbeddedModelBundle.directory?.standardizedFileURL)
    }

    @Test func rolloutUsesAStableDeviceBucket() async throws {
        try publish("1.1.0", rollout: 0)
        #expect(await updater().check() == .upToDate)
        let bucket = ModelUpdater.rolloutBucket(deviceId: "device-1", version: "1.1.0")
        #expect(bucket == ModelUpdater.rolloutBucket(deviceId: "device-1", version: "1.1.0"))
        #expect((0..<100).contains(bucket))
        let buckets = Set((0..<500).map { ModelUpdater.rolloutBucket(deviceId: "d\($0)", version: "1.1.0") })
        #expect(buckets.count > 90)
        source.records = source.records.map { var row = $0; row.rolloutPercent = bucket + 1; return row }
        #expect(await updater().check() == .updated(from: "1.0.0", to: "1.1.0"))
    }

    @Test func checksAtMostOncePerInterval() async throws {
        let clock = Clock()
        let updater = updater { clock.now }
        #expect(await updater.checkIfDue() == .upToDate)
        clock.now += 3600
        #expect(await updater.checkIfDue() == .notDue)
        clock.now += 24 * 3600
        #expect(await updater.checkIfDue() == .upToDate)
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }
}
#endif
