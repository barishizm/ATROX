import DataKit
import DesignSystem
import Foundation
import StrengthKit
import SwiftData

/// Score orchestration wiring of the composition root (P064).
extension AppContainer {
    /// Every local save (a finished workout, an edited set, a new weigh-in, a changed profile or reference group)
    /// asks for a debounced score refresh; `ScoreService.refresh` does nothing when no score input changed.
    func scoresMayHaveChanged() {
        guard scoreService != nil else { return }
        scoreRefreshTask?.cancel()
        scoreRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refreshScores()
        }
    }

    func refreshScores() async {
        guard let center = await scoreCenter(), let user = await currentUser() else { return }
        await center.refresh(userId: user.id)
        await rescheduleWeeklySummary()
    }

    /// The score state of the signed-in user; the first call per user backfills history and computes everything.
    func scoreCenter() async -> ScoreCenter? {
        guard let service = scoreService, let user = await currentUser() else { return nil }
        if let existing = scoreCenterState, existing.userId == user.id { return existing.center }
        let center = ScoreCenter(service: service, updater: modelUpdater)
        scoreCenterState = (user.id, center)
        await center.start(userId: user.id)
        return center
    }

    /// Launch / foreground / sign-in: makes sure scores exist and are current (also picks up a new model version).
    func prepareScores() async {
        guard let center = await scoreCenter(), let user = await currentUser() else { return }
        await center.refresh(userId: user.id)
    }

    func resetScores() async {
        scoreRefreshTask?.cancel()
        scoreCenterState = nil
        insightServiceState = nil
        await scoreService?.reset()
    }

    /// Muscle heat map and list of the Analysis tab (P066); nil without a user or local store.
    func makeMuscleAnalysisModel() async -> MuscleAnalysisModel? {
        guard let modelContainer, let center = await scoreCenter(), let user = await currentUser() else { return nil }
        return MuscleAnalysisModel(userId: user.id, center: center, stats: TrainingStats(modelContainer: modelContainer))
    }

    /// Progress charts of the Analysis tab (P068); nil without a user or local store.
    func makeProgressModel() async -> ProgressModel? {
        guard let modelContainer, let center = await scoreCenter(), let context = await makeHistoryContext() else { return nil }
        return ProgressModel(context: context, center: center, stats: TrainingStats(modelContainer: modelContainer))
    }

    func makeMuscleDetailModel(muscle: Muscle) async -> MuscleDetailModel? {
        guard let modelContainer, let service = scoreService, let center = await scoreCenter(),
              let context = await makeHistoryContext() else { return nil }
        return MuscleDetailModel(
            muscle: muscle, userId: context.userId, service: service, stats: TrainingStats(modelContainer: modelContainer),
            center: center, names: context.loadNames
        )
    }

    static func makeScoreService(
        store: ModelContainer?, updater: ModelUpdater?, appVersion: String
    ) -> ScoreService? {
        guard let store else { return nil }
        let provider = ScoringModelProvider(updater: updater, appVersion: appVersion)
        return ScoreService(modelContainer: store, scoringModel: { await provider.current() })
    }
}
