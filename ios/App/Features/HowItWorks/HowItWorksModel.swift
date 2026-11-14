import Foundation
import Observation
import StrengthKit

/// Model version block of the "How is it calculated?" screen (P071).
@MainActor
@Observable
final class HowItWorksModel {
    enum UpdateState: Equatable {
        case idle, checking, upToDate, updated(String), failed
    }

    private(set) var info: ScoringModelInfo?
    private(set) var isLoaded = false
    private(set) var update: UpdateState = .idle
    /// False without Supabase (the embedded bundle is all there is), so there is nothing to check.
    let canCheck: Bool

    @ObservationIgnored private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        canCheck = container.modelUpdater != nil
    }

    func load() async {
        info = await container.scoringModelInfo()
        isLoaded = true
    }

    func checkForUpdate() async {
        update = .checking
        let outcome = await container.checkModelUpdateNow()
        info = await container.scoringModelInfo()
        update = switch outcome {
        case .updated(_, let to), .rolledBack(_, let to): .updated(to)
        case .upToDate, .notDue: .upToDate
        case .failed, nil: .failed
        }
    }
}
