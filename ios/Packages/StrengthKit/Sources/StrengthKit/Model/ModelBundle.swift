import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A model bundle on disk (`manifest.json`, `manifest.sig`, `params.json`, `taxonomy.json`, `anchor_tables.json`, ...).
/// `load` verifies the Ed25519 signature over the manifest, every file's SHA-256, the schema version and the minimum app
/// version before anything is decoded (docs/03-ML-MODEL.md §11).
public struct ModelBundle: Sendable {
    /// Ed25519 public key (raw, base64) that signs model bundles. Private key: see docs/KURULUM.md.
    public static let trustedPublicKeyBase64 = "BkYuzm+Izi7IbGVvSGTa/u/qsP5ki542VwSlnr4llbM="
    public static let format = "atrox-model-bundle/1"

    public struct Manifest: Codable, Sendable, Equatable {
        public struct Anchor: Codable, Sendable, Equatable {
            /// tables | coreml
            public let kind: String
            public let file: String
        }

        public let format: String
        public let version: String
        public let schemaVersion: Int
        public let minAppVersion: String
        public let anchor: Anchor
        /// file name → lowercase hex SHA-256
        public let files: [String: String]
    }

    public let directory: URL
    public let manifest: Manifest
    public let model: StrengthModel

    /// Loads and verifies a bundle. Throws `.bundle` for any signature, digest, format or compatibility problem.
    public static func load(
        from directory: URL, appVersion: String, publicKeyBase64: String = trustedPublicKeyBase64
    ) throws(StrengthModelError) -> ModelBundle {
        let manifestData = try read(directory, "manifest.json")
        let signature = try read(directory, "manifest.sig")
        try verifySignature(signature, over: manifestData, publicKeyBase64: publicKeyBase64)
        let manifest: Manifest = try decodeJSON(manifestData)
        guard manifest.format == format else { throw .bundle("unsupported bundle format \(manifest.format)") }
        guard manifest.schemaVersion == ModelParams.supportedSchemaVersion else {
            throw .unsupportedSchema(found: manifest.schemaVersion, supported: ModelParams.supportedSchemaVersion)
        }
        guard let minApp = SemanticVersion(manifest.minAppVersion), let app = SemanticVersion(appVersion) else {
            throw .bundle("malformed version")
        }
        guard app >= minApp else { throw .bundle("bundle needs app \(manifest.minAppVersion), running \(appVersion)") }
        var files: [String: Data] = [:]
        for (name, digest) in manifest.files {
            guard !name.contains("/"), !name.hasPrefix(".") else { throw .bundle("invalid file name \(name)") }
            let data = try read(directory, name)
            guard try sha256Hex(data) == digest.lowercased() else { throw .bundle("SHA-256 mismatch for \(name)") }
            files[name] = data
        }
        guard manifest.anchor.kind == "tables" else { throw .bundle("anchor kind \(manifest.anchor.kind) not supported") }
        guard let params = files["params.json"], let taxonomy = files["taxonomy.json"],
              let tables = files[manifest.anchor.file] else {
            throw .bundle("bundle is missing a required file")
        }
        let model = try StrengthModel(
            params: ModelParams.decode(params), taxonomy: ModelTaxonomy.decode(taxonomy), anchor: TableAnchorDistribution(data: tables)
        )
        return ModelBundle(directory: directory, manifest: manifest, model: model)
    }

    /// The verified embedded base bundle.
    public static func embedded(appVersion: String) throws(StrengthModelError) -> ModelBundle {
        guard let directory = EmbeddedModelBundle.directory else { throw .bundle("embedded bundle missing") }
        return try load(from: directory, appVersion: appVersion)
    }

    /// Prefers `candidate` (e.g. the downloaded active bundle) and falls back to the embedded bundle when it is missing,
    /// tampered with or incompatible.
    public static func loadPreferred(candidate: URL?, appVersion: String) throws(StrengthModelError) -> ModelBundle {
        if let candidate, let bundle = try? load(from: candidate, appVersion: appVersion) { return bundle }
        return try embedded(appVersion: appVersion)
    }

    private static func read(_ directory: URL, _ name: String) throws(StrengthModelError) -> Data {
        do {
            return try Data(contentsOf: directory.appendingPathComponent(name))
        } catch {
            throw .bundle("cannot read \(name)")
        }
    }

    static func verifySignature(_ signature: Data, over message: Data, publicKeyBase64: String) throws(StrengthModelError) {
        #if canImport(CryptoKit)
        guard let raw = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            throw .bundle("invalid public key")
        }
        guard key.isValidSignature(signature, for: message) else { throw .bundle("manifest signature is invalid") }
        #else
        throw .bundle("signature verification needs CryptoKit")
        #endif
    }

    static func sha256Hex(_ data: Data) throws(StrengthModelError) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        throw .bundle("SHA-256 needs CryptoKit")
        #endif
    }
}

/// `major.minor.patch` with numeric ordering.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let parts = text.split(separator: ".").map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.compactMap(\.self)
    }

    private init(parts: [Int]) {
        self.parts = parts
    }

    public static let zero = SemanticVersion(parts: [0, 0, 0])

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
