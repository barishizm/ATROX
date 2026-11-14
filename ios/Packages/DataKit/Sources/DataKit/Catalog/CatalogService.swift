import Foundation
import SwiftData

/// Keeps the local exercise catalog current (P028):
///  1. `bootstrap()` — first launch (or an app update with a newer file) imports the bundled `catalog.v{N}.json`;
///  2. `syncRemote()` — compares `catalog_versions` on the server with the local version and, only if the server is
///     newer, fetches just the exercises changed since the installed version was published.
/// Both run on a background context; neither touches user data, so existing workouts are never affected.
public struct CatalogService: Sendable {
    public typealias PackageLoader = @Sendable () throws -> CatalogPackage

    private let importer: CatalogImporter
    private let loadBundled: PackageLoader
    /// Version of the bundled file read from its name alone; nil when unknown (then the file is decoded to find out).
    private let bundledVersion: @Sendable () -> Int?
    private let remote: (any CatalogRemote)?
    private let clock: @Sendable () -> Date

    public init(
        modelContainer: ModelContainer,
        bundled: PackageLoader? = nil,
        bundledVersion: (@Sendable () -> Int?)? = nil,
        remote: (any CatalogRemote)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        importer = CatalogImporter(modelContainer: modelContainer)
        loadBundled = bundled ?? { try BundledCatalog.load() }
        // Only the real bundle can be checked by file name; an injected loader is always decoded unless told otherwise.
        if let bundledVersion {
            self.bundledVersion = bundledVersion
        } else if bundled == nil {
            self.bundledVersion = { BundledCatalog.bundledVersion() }
        } else {
            self.bundledVersion = { nil }
        }
        self.remote = remote
        self.clock = clock
    }

    public func installedVersion() async throws -> Int? {
        try await importer.installedInfo()?.version
    }

    @discardableResult
    public func bootstrap() async throws -> CatalogBootstrapResult {
        let installed = try await importer.installedInfo()
        // Every launch after the first: the file name already says nothing newer is bundled, so skip decoding ~2 MB (P098).
        if let installed, let bundled = bundledVersion(), installed.version >= bundled {
            return .upToDate(version: installed.version)
        }
        let package = try loadBundled()
        if let installed, installed.version >= package.version {
            return .upToDate(version: installed.version)
        }
        // A newer bundled file also covers anything the server had so far; archive logic runs on the full list.
        let count = try await importer.apply(
            package.exercises, mode: .full, version: package.version, checksum: package.checksum, now: clock())
        return .imported(version: package.version, count: count)
    }

    @discardableResult
    public func syncRemote() async throws -> CatalogSyncResult {
        guard let remote else { return .notInstalled }
        guard let installed = try await importer.installedInfo() else { return .notInstalled }
        guard let latest = try await remote.latestVersion(), latest.version > installed.version else {
            return .upToDate(version: installed.version)
        }
        // Changes since the installed version went live; if the server does not know that version, fetch everything.
        let since = try await remote.version(installed.version)?.publishedAt ?? "1970-01-01T00:00:00+00:00"
        let changed = try await remote.changes(since: since)
        try await importer.apply(changed, mode: .delta, version: latest.version, checksum: latest.checksum, now: clock())
        return .updated(from: installed.version, to: latest.version, changed: changed.count)
    }
}

/// Finds and decodes the catalog file bundled with the app.
public enum BundledCatalog {
    /// `catalog.v{N}.json` with the highest N, in the bundle root or a `Catalog` folder.
    public static func url(in bundle: Bundle = .main) -> URL? {
        let candidates = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Catalog") ?? [])
        return candidates
            .compactMap { url in version(ofFileNamed: url.lastPathComponent).map { ($0, url) } }
            .max { $0.0 < $1.0 }?.1
    }

    public static func version(ofFileNamed name: String) -> Int? {
        guard name.hasPrefix("catalog.v"), name.hasSuffix(".json") else { return nil }
        return Int(name.dropFirst("catalog.v".count).dropLast(".json".count))
    }

    /// Version of the bundled file taken from its name, without reading the file.
    public static func bundledVersion(in bundle: Bundle = .main) -> Int? {
        url(in: bundle).flatMap { version(ofFileNamed: $0.lastPathComponent) }
    }

    public static func load(bundle: Bundle = .main) throws -> CatalogPackage {
        guard let url = url(in: bundle) else { throw CatalogError.bundledCatalogMissing }
        return try CatalogPackage.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
}
