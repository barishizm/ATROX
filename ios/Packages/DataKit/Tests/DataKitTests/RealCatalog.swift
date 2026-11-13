@testable import DataKit
import Foundation

/// The catalog file shipped in `ios/App/Resources/Catalog`. Picks `catalog.v{N}.json` with the highest N, the same
/// rule as `BundledCatalog.url(in:)`, so a catalog rebuild (new version number) does not break the tests.
let realCatalogURL: URL = {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Catalog")
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let latest = files
        .compactMap { url in BundledCatalog.version(ofFileNamed: url.lastPathComponent).map { ($0, url) } }
        .max { $0.0 < $1.0 }?.1
    return latest ?? dir.appendingPathComponent("catalog.v1.json")
}()
