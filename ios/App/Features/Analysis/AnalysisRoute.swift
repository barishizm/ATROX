import Foundation

enum AnalysisRoute: Hashable, Sendable {
    case exerciseDetail(catalogId: String)
    /// Muscle detail page; the value is the catalog muscle name (`"lower_back"`).
    case muscle(String)
    case exerciseScore(catalogId: String)
}
