import DataKit
import DesignSystem
import SwiftUI

/// Friends ranking (P087): tabs for score, workouts this week and progress this month. My row is highlighted.
/// Only the published score, workout count or change appears here, never body weight or lifts.
struct SocialRankingView: View {
    @State private var model: SocialRankingModel

    init(service: any SocialService) { _model = State(initialValue: SocialRankingModel(service: service)) }

    var body: some View {
        List {
            Section {
                Picker("social.ranking.title", selection: Binding(get: { model.period }, set: { tab in Task { await model.select(tab) } })) {
                    Text("social.ranking.tab.score").tag(RankingPeriod.score)
                    Text("social.ranking.tab.weekly").tag(RankingPeriod.weekly)
                    Text("social.ranking.tab.month").tag(RankingPeriod.month)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ranking-tabs")
            }
            switch model.phase {
            case .loading: Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed: Section { Text("social.error.generic").foregroundStyle(DSColor.error) }
            case .ready: rows
            }
        }
        .navigationTitle("social.ranking.title")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
        .accessibilityIdentifier("social-ranking")
    }

    @ViewBuilder private var rows: some View {
        Section {
            ForEach(model.current) { entry in
                RankingRow(entry: entry, period: model.period)
            }
            if !model.hasCompetition {
                Text("social.ranking.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("ranking-empty")
            }
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if model.period != .weekly, model.myValueMissing { Text("social.ranking.sharing.hint") }
                // Scores are already normalised by sex, age and body weight, so everyone competes on equal terms.
                Text("social.ranking.fair")
            }
        }
    }
}

struct RankingRow: View {
    let entry: RankingEntry
    let period: RankingPeriod

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: entry.value == nil ? "–" : "\(entry.rank)")
                .font(DSFont.numericMedium).foregroundStyle(DSColor.textSecondary).frame(width: 28)
            AvatarView(emoji: entry.avatarEmoji, color: entry.avatarColor, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.displayName).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text(verbatim: "@\(entry.username)").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            if let value = entry.value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: SocialRankingModel.valueText(value, period: period)).font(DSFont.numericMedium).foregroundStyle(DSColor.accent)
                    if entry.isProvisional {
                        // A provisional score is still settling: too few lifts for the full picture.
                        Text("social.ranking.provisional").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
        }
        .frame(minHeight: HitTarget.minimum)
        .listRowBackground(entry.isMe ? DSColor.accent.opacity(0.14) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(entry.isMe ? "ranking-row-me" : "ranking-row")
    }
}
