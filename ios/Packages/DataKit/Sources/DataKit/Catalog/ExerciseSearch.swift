import Foundation

/// Value-type projection of `Exercise` for the library list: cheap to copy, `Sendable`, and carries everything the
/// search/filter code needs pre-folded so every keystroke only does string comparisons (P030).
public struct ExerciseListItem: Sendable, Identifiable, Hashable {
    public let id: String
    public let nameEn: String
    public let nameTr: String
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    /// nil in the catalog means "no equipment" (bodyweight); filters see it as `ExerciseFilter.noEquipmentToken`.
    public let equipment: String?
    public let isScorable: Bool
    public let thumbnailName: String?
    /// Folded names + aliases of both languages.
    let searchText: String
    let foldedNames: [String]
    let words: [String]

    public init(
        id: String, nameEn: String, nameTr: String, aliases: [String] = [],
        primaryMuscles: [String] = [], secondaryMuscles: [String] = [], equipment: String? = nil,
        isScorable: Bool = false, thumbnailName: String? = nil
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameTr = nameTr
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.isScorable = isScorable
        self.thumbnailName = thumbnailName
        let names = [SearchFolding.fold(nameEn), SearchFolding.fold(nameTr)]
        foldedNames = names
        searchText = ([nameEn, nameTr] + aliases).map(SearchFolding.fold).joined(separator: " ")
        words = ExerciseSearch.words(of: searchText)
    }

    public init(_ exercise: Exercise) {
        self.init(
            id: exercise.id, nameEn: exercise.nameEn, nameTr: exercise.nameTr,
            aliases: exercise.aliasesEn + exercise.aliasesTr,
            primaryMuscles: exercise.primaryMuscles, secondaryMuscles: exercise.secondaryMuscles,
            equipment: exercise.equipment,
            isScorable: exercise.scoringTypeRaw != "none",
            thumbnailName: exercise.imagePaths.first.map(ImageNaming.thumb(forFull:))
        )
    }

    public func name(languageCode: String) -> String { languageCode == "tr" ? nameTr : nameEn }
    public var primaryMuscle: String? { primaryMuscles.first }
}

/// Muscle / equipment / scorable filters; the three combine with AND, values inside one group with OR.
public struct ExerciseFilter: Sendable, Equatable {
    public static let noEquipmentToken = "none"

    public var muscles: Set<String>
    public var equipment: Set<String>
    public var scorableOnly: Bool

    public init(muscles: Set<String> = [], equipment: Set<String> = [], scorableOnly: Bool = false) {
        self.muscles = muscles
        self.equipment = equipment
        self.scorableOnly = scorableOnly
    }

    public var isActive: Bool { !muscles.isEmpty || !equipment.isEmpty || scorableOnly }
    public var activeCount: Int { (muscles.isEmpty ? 0 : 1) + (equipment.isEmpty ? 0 : 1) + (scorableOnly ? 1 : 0) }

    public func matches(_ item: ExerciseListItem) -> Bool {
        if scorableOnly, !item.isScorable { return false }
        if !muscles.isEmpty, muscles.isDisjoint(with: item.primaryMuscles) { return false }
        if !equipment.isEmpty, !equipment.contains(item.equipment ?? Self.noEquipmentToken) { return false }
        return true
    }

    /// Equipment the user can realistically use, derived from onboarding's "equipment access" answer.
    /// nil = no restriction (full gym).
    public static func suggestedEquipment(for access: EquipmentAccess) -> Set<String>? {
        let none = noEquipmentToken
        switch access {
        case .fullGym: return nil
        case .homeBarbell: return ["barbell", "ez_bar", "dumbbell", "body_only", "bands", "kettlebell", "foam_roll", none]
        case .homeDumbbell: return ["dumbbell", "kettlebell", "body_only", "bands", "foam_roll", none]
        case .bodyweightOnly: return ["body_only", "bands", "foam_roll", none]
        }
    }

    /// A default filter for the user's equipment access (empty for a full gym).
    public static func suggested(for access: EquipmentAccess) -> ExerciseFilter {
        ExerciseFilter(equipment: suggestedEquipment(for: access) ?? [])
    }
}

public enum ExerciseSearch {
    /// Lower is better. Tiers: 0 name prefix, 1 name word-start, 2 name contains, 3 alias/any word-start,
    /// 4 alias/any contains, 5 typo-tolerant (one edit per token).
    enum Tier: Int { case namePrefix, nameWord, nameContains, aliasWord, aliasContains, typo }

    /// Items matching `query` best first; an empty query returns `items` unchanged. Accent, case and Turkish
    /// dotted/dotless i are ignored, so "sinav" finds "Şınav".
    public static func rank(query: String, in items: [ExerciseListItem]) -> [ExerciseListItem] {
        let folded = SearchFolding.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return items }
        let tokens = words(of: folded)
        var scored: [(item: ExerciseListItem, tier: Int, length: Int)] = []
        for item in items {
            if let tier = tier(of: item, query: folded, tokens: tokens) {
                scored.append((item, tier.rawValue, item.foldedNames.map(\.count).min() ?? 0))
            }
        }
        scored.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.item.id < $1.item.id
        }
        return scored.map(\.item)
    }

    static func tier(of item: ExerciseListItem, query: String, tokens: [String]) -> Tier? {
        for name in item.foldedNames {
            if name.hasPrefix(query) { return .namePrefix }
        }
        let nameWords = item.foldedNames.map(words(of:))
        if nameWords.contains(where: { $0.contains { $0.hasPrefix(query) } }) { return .nameWord }
        if tokens.count > 1, nameWords.contains(where: { allTokensPrefix(tokens, in: $0) }) { return .nameWord }
        if item.foldedNames.contains(where: { $0.contains(query) }) { return .nameContains }
        if item.words.contains(where: { $0.hasPrefix(query) }) || allTokensPrefix(tokens, in: item.words) { return .aliasWord }
        if item.searchText.contains(query) { return .aliasContains }
        if tokens.allSatisfy({ token in item.words.contains { fuzzyPrefix(token, of: $0) } }) { return .typo }
        return nil
    }

    private static func allTokensPrefix(_ tokens: [String], in words: [String]) -> Bool {
        tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
    }

    static func words(of text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// True when `token` is within one edit (insert/delete/substitute/transposition) of the start of `word`.
    /// Only for tokens of 4+ characters, otherwise short queries would match everything.
    static func fuzzyPrefix(_ token: String, of word: String) -> Bool {
        let t = Array(token), w = Array(word)
        guard t.count >= 4, w.count >= t.count - 1 else { return false }
        for length in max(1, t.count - 1)...min(w.count, t.count + 1) {
            if editDistanceAtMostOne(t, Array(w.prefix(length))) { return true }
        }
        return false
    }

    static func editDistanceAtMostOne(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return true }
        if abs(a.count - b.count) > 1 { return false }
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        if a.count == b.count {
            if Array(a[(i + 1)...]) == Array(b[(i + 1)...]) { return true }
            if i + 1 < a.count, a[i] == b[i + 1], a[i + 1] == b[i], Array(a[(i + 2)...]) == Array(b[(i + 2)...]) { return true }
            return false
        }
        let (long, short) = a.count > b.count ? (a, b) : (b, a)
        return Array(long[(i + 1)...]) == Array(short[i...])
    }
}
