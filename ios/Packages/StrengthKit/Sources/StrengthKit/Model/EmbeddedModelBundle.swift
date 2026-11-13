import Foundation

/// The base model bundle shipped inside StrengthKit (`Resources/ModelBundle`, written by ml `make export`).
/// Works offline from first launch; signature checks live in `ModelBundle`.
public enum EmbeddedModelBundle {
    public static var directory: URL? {
        Bundle.module.url(forResource: "ModelBundle", withExtension: nil)
    }

    static func read(_ name: String) throws(StrengthModelError) -> Data {
        guard let url = directory?.appendingPathComponent(name) else { throw .bundle("embedded bundle missing") }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .bundle("embedded \(name): \(error)")
        }
    }

    public static func params() throws(StrengthModelError) -> ModelParams {
        try ModelParams.decode(read("params.json"))
    }

    /// Score model of the embedded bundle (no signature check: the files ship inside the signed app).
    public static func model() throws(StrengthModelError) -> StrengthModel {
        try StrengthModel(
            params: params(),
            taxonomy: ModelTaxonomy.decode(read("taxonomy.json")),
            anchor: TableAnchorDistribution(data: read("anchor_tables.json"))
        )
    }
}
