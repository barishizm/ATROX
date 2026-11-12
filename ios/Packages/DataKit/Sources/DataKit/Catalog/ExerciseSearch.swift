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
    /// A user-created exercise (its `id` is the UUID string).
    public let isCustom: Bool
    /// Folded names + aliases of both languages.
    let searchText: String
    let foldedNames: [String]
    let words: [String]

    public init(
        id: String, nameEn: String, nameTr: String, aliases: [String] = [],
        primaryMuscles: [String] = [], secondaryMuscles: [String] = [], equipment: String? = nil,
        isScorable: Bool = false, thumbnailName: String? = nil, isCustom: Bool = false
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameTr = nameTr
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.isScorable = isScorable
        self.thumbnailName = thumbnailName
        self.isCustom = isCustom
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

    public init(_ custom: CustomExercise) {
        self.init(
            id: custom.id.uuidString, nameEn: custom.name, nameTr: custom.name, aliases: custom.aliases,
            primaryMuscles: custom.primaryMuscles, secondaryMuscles: custom.secondaryMuscles,
            equipment: custom.equipment, isScorable: custom.scoringTypeRaw != "none", isCustom: true
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
    private struct Scored {
        let item: ExerciseListItem
        let tier: Int
        let length: Int
    }

    /// Lower is better. Tiers: 0 name prefix, 1 name word-start, 2 name contains, 3 alias/any word-start,
    /// 4 alias/any contains, 5 typo-tolerant (one edit per token).
    enum Tier: Int { case namePrefix, nameWord, nameContains, aliasWord, aliasContains, typo }

    /// Items matching `query` best first; an empty query returns `items` unchanged. Accent, case and Turkish
    /// dotted/dotless i are ignored, so "sinav" finds "Şınav".
    public static func rank(query: String, in items: [ExerciseListItem]) -> [ExerciseListItem] {
        let folded = SearchFolding.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return items }
        let tokens = words(of: folded)
        var scored: [Scored] = []
        for item in items {
            guard let tier = tier(of: item, query: folded, tokens: tokens) else { continue }
            scored.append(Scored(item: item, tier: tier.rawValue, length: item.foldedNames.map(\.count).min() ?? 0))
        }
        scored.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.length != $1.length { return $0.length < $1.length }
            return $0.item.id < $1.item.id
        }
        return scored.map(\.item)
    }

    static func tier(of item: ExerciseListItem, query: String, tokens: [String]) -> Tier? {
        if item.foldedNames.contains(where: { $0.hasPrefix(query) }) { return .namePrefix }
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
        let wanted = Array(token), candidate = Array(word)
        guard wanted.count >= 4, candidate.count >= wanted.count - 1 else { return false }
        return (max(1, wanted.count - 1)...min(candidate.count, wanted.count + 1)).contains {
            editDistanceAtMostOne(wanted, Array(candidate.prefix($0)))
        }
    }

    static func editDistanceAtMostOne(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        if lhs == rhs { return true }
        if abs(lhs.count - rhs.count) > 1 { return false }
        var index = 0
        while index < lhs.count, index < rhs.count, lhs[index] == rhs[index] { index += 1 }
        if lhs.count == rhs.count {
            if Array(lhs[(index + 1)...]) == Array(rhs[(index + 1)...]) { return true }
            let swapped = index + 1 < lhs.count && lhs[index] == rhs[index + 1] && lhs[index + 1] == rhs[index]
            return swapped && Array(lhs[(index + 2)...]) == Array(rhs[(index + 2)...])
        }
        let (long, short) = lhs.count > rhs.count ? (lhs, rhs) : (rhs, lhs)
        return Array(long[(index + 1)...]) == Array(short[index...])
    }
}
