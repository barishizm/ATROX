import Foundation

/// Picks catalog exercises that train the muscles an insight is about ("Add a pulling exercise to your program").
public enum InsightSuggestions {
    /// Catalog exercises (not custom ones) whose primary muscles include one of `muscles`, scorable ones first, then
    /// the ones that cover more of the wanted muscles, then by name. `exclude` holds ids to skip (already in use).
    public static func pick(
        from items: [ExerciseListItem], muscles: [String], exclude: Set<String> = [], limit: Int = 4, languageCode: String = "en"
    ) -> [ExerciseListItem] {
        let wanted = Set(muscles)
        guard !wanted.isEmpty else { return [] }
        func coverage(_ item: ExerciseListItem) -> Int { Set(item.primaryMuscles).intersection(wanted).count }
        return Array(
            items.filter { !$0.isCustom && !exclude.contains($0.id) && coverage($0) > 0 }
                .sorted {
                    if $0.isScorable != $1.isScorable { return $0.isScorable }
                    if coverage($0) != coverage($1) { return coverage($0) > coverage($1) }
                    let (lhs, rhs) = ($0.name(languageCode: languageCode), $1.name(languageCode: languageCode))
                    return lhs != rhs ? lhs < rhs : $0.id < $1.id
                }
                .prefix(max(0, limit))
        )
    }
}
