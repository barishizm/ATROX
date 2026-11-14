import DataKit
import Foundation
import Observation

/// State of the friends ranking (P087): one list per tab, loaded on demand and on pull to refresh.
@MainActor
@Observable
final class SocialRankingModel {
    enum Phase: Equatable {
        case loading
        case failed
        case ready
    }

    var period: RankingPeriod = .score
    private(set) var phase: Phase = .loading
    private(set) var entries: [RankingPeriod: [RankingEntry]] = [:]

    @ObservationIgnored private let service: any SocialService

    init(service: any SocialService) { self.service = service }

    var current: [RankingEntry] { entries[period] ?? [] }

    /// Someone with a value to show; a ranking of only me (or nobody sharing) reads as empty.
    var hasCompetition: Bool { current.filter { $0.value != nil }.count > 1 }

    /// My own row on this tab has no value: score sharing is off, or nothing was published yet.
    var myValueMissing: Bool { current.first(where: \.isMe)?.value == nil }

    func load() async {
        let tab = period
        do {
            entries[tab] = try await service.ranking(tab)
            phase = .ready
        } catch {
            if entries[tab] == nil { phase = .failed }
        }
    }

    /// Switching tabs loads that tab the first time it is shown.
    func select(_ tab: RankingPeriod) async {
        period = tab
        if entries[tab] == nil {
            phase = .loading
            await load()
        } else {
            phase = .ready
        }
    }

    /// "+3" for monthly progress, plain numbers elsewhere.
    static func valueText(_ value: Int, period: RankingPeriod) -> String {
        period == .month && value > 0 ? "+\(value)" : "\(value)"
    }
}
