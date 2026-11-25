import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// The overall 0–100 strength score card on the Workout tab (P067). Its model also feeds the widgets and publishes
/// the score to the social layer.
struct TodayRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: TodayModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                if model.isLoading { LoadingState() } else { scoreCard(model) }
            } else if failed {
                ErrorState(message: "today.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .frame(maxWidth: .infinity)
        .howItWorksButton()
        .task(id: container.unitRevision) { await prepare(rebuild: container.unitRevision > 0) }
        .task(id: TodayReload(data: container.dataRevision, plan: model?.planSignature)) { await model?.load() }
        .accessibilityIdentifier("today-root")
    }

    // MARK: Score

    @ViewBuilder
    private func scoreCard(_ model: TodayModel) -> some View {
        switch model.status {
        case .noData: noScoreCard(model)
        case .provisional(let missing): scoreHero(model, provisional: true, missing: missing)
        case .full: scoreHero(model, provisional: false, missing: [])
        }
    }

    private func scoreHero(_ model: TodayModel, provisional: Bool, missing: [String]) -> some View {
        Card {
            VStack(spacing: Spacing.md) {
                HStack {
                    Text("today.score.title").font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    if let overall = model.overall, !provisional {
                        OverallShareButton(score: overall.score, population: model.population)
                    }
                }
                if let overall = model.overall {
                    ScoreRing(score: overall.score, diameter: 190, lineWidth: 16).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("today-score-ring")
                }
                if provisional { TagChip("today.score.provisional", systemImage: "hourglass", style: .warning) }
                changeText(model)
                if provisional { provisionalHint(model, missing: missing) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-card")
    }

    @ViewBuilder
    private func changeText(_ model: TodayModel) -> some View {
        if let change = model.facts?.overallChange, abs(change) >= 0.5 {
            let value = Int(change.rounded())
            Text("today.score.change \(value > 0 ? "+\(value)" : "\(value)")")
                .font(DSFont.callout).foregroundStyle(value > 0 ? DSColor.success : DSColor.textSecondary)
                .accessibilityIdentifier("today-score-change")
        }
    }

    private func provisionalHint(_ model: TodayModel, missing: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("today.score.provisional.body").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            if let name = model.hintName {
                Label("today.score.hint \(name)", systemImage: "plus.circle")
                    .font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.accent)
                    .accessibilityIdentifier("today-score-hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noScoreCard(_ model: TodayModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("today.score.title").font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
                Text(noScoreMessage(model)).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today-score-empty")
    }

    private func noScoreMessage(_ model: TodayModel) -> LocalizedStringKey {
        switch model.unavailable {
        case .noBodyweight: "today.score.none.weight"
        case .noProfile: "today.score.none.profile"
        case .noModel: "score.unavailable.model"
        default: "today.score.none"
        }
    }

    private func prepare(rebuild: Bool = false) async {
        if rebuild { model = nil }
        guard model == nil else { return }
        guard let created = await container.makeTodayModel() else {
            failed = true
            return
        }
        model = created
        await created.load()
    }
}

/// What makes the Today tab reload: new data, or a changed active program or weekly plan.
private struct TodayReload: Hashable {
    let data: AppContainer.DataRevision
    let plan: String?
}
