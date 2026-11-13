import Foundation
import StrengthKit

/// One muscle's score and the exercises behind it (P066).
public struct MuscleDetail: Sendable, Equatable {
    public var score: GroupScore?
    public var contributions: [MuscleContribution]
}

extension ScoreService {
    /// Detail of one muscle under the user's preferred reference group; nil while scoring is unavailable.
    public func muscleDetail(userId: UUID, muscle: String) async -> MuscleDetail? {
        guard case .ready(let overview) = await overview(userId: userId), let scoring = await currentScoringModel() else { return nil }
        return MuscleDetail(
            score: overview.muscles[muscle],
            contributions: MuscleContributions.contributions(muscle: muscle, overview: overview, model: scoring.model)
        )
    }
}
