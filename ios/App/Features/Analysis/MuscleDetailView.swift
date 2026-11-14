import Charts
import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// One muscle (P066): score, contributing exercises with their weights, weekly sets of the last four weeks, trend.
struct MuscleDetailView: View {
    let muscleName: String
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: MuscleDetailModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if failed {
                ErrorState(message: "muscles.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle(Muscle(rawValue: muscleName)?.localizedName(locale: locale) ?? muscleName)
        .navigationBarTitleDisplayMode(.inline)
        .howItWorksButton()
        .task { await prepare() }
        .accessibilityIdentifier("muscle-detail-root")
    }

    private func content(_ model: MuscleDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero(model)
                MuscleMapView(primary: [model.muscle], style: .default)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .accessibilityHidden(true)
                weeklySection(model)
                contributionsSection(model)
            }
            .padding(Spacing.md)
        }
    }

    // MARK: Score

    @ViewBuilder
    private func hero(_ model: MuscleDetailModel) -> some View {
        if let score = model.score {
            VStack(spacing: Spacing.sm) {
                ScoreRing(score: score).frame(maxWidth: .infinity)
                if let change = model.change, abs(change) >= 0.5 {
                    let value = Int(change.rounded())
                    Text("muscles.detail.trend \(value > 0 ? "+\(value)" : "\(value)")")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("muscle-trend")
                }
            }
        } else {
            Card {
                Text("muscles.detail.noScore").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    // MARK: Weekly volume

    private func weeklySection(_ model: MuscleDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("muscles.detail.weekly").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Chart(model.weeklyBars, id: \.weeksAgo) { bar in
                        BarMark(x: .value("week", weekLabel(bar.weeksAgo)), y: .value("sets", bar.sets))
                            .foregroundStyle(DSColor.accent)
                            .annotation(position: .top) {
                                Text(verbatim: MuscleFormat.sets(bar.sets, locale: locale)).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                            }
                    }
                    .frame(height: 140)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("muscles.detail.weekly.a11y \(weeklySummary(model))"))
                    Text("muscles.detail.weekAxis").font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                    Text("muscles.detail.week7 \(MuscleFormat.sets(model.last7Days, locale: locale))")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    Text("muscles.detail.rule").font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                }
            }
            .accessibilityIdentifier("muscle-weekly")
        }
    }

    private func weekLabel(_ weeksAgo: Int) -> String {
        weeksAgo == 0 ? "0" : "−\(weeksAgo)"
    }

    private func weeklySummary(_ model: MuscleDetailModel) -> String {
        model.weeklyBars.map { MuscleFormat.sets($0.sets, locale: locale) }.joined(separator: ", ")
    }

    // MARK: Contributions

    private func contributionsSection(_ model: MuscleDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("muscles.detail.contributions").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            let items = model.detail?.contributions ?? []
            if items.isEmpty {
                Card { Text("muscles.detail.noContributions").font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
            } else {
                ForEach(items) { item in
                    NavigationLink(value: AnalysisRoute.exerciseScore(catalogId: item.exerciseId)) {
                        Card(padding: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(verbatim: model.name(of: item.exerciseId)).font(DSFont.callout.weight(.semibold))
                                        .foregroundStyle(DSColor.textPrimary).multilineTextAlignment(.leading)
                                    Text(LocalizedStringKey("muscles.role.\(item.role.rawValue)"))
                                        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                                }
                                Spacer(minLength: Spacing.sm)
                                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                    Text(verbatim: "\(Int(item.score.rounded()))").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                                    Text(verbatim: item.share.formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                                        .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                                }
                            }
                            .frame(minHeight: HitTarget.minimum - Spacing.md)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
                Text("muscles.detail.shareNote").font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
            }
        }
    }

    private func prepare() async {
        guard model == nil, let muscle = Muscle(rawValue: muscleName) else { return }
        guard let created = await container.makeMuscleDetailModel(muscle: muscle) else {
            failed = true
            return
        }
        model = created
        await created.load()
    }
}
