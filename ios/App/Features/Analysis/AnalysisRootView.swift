import DataKit
import DesignSystem
import SwiftUI

/// The Analysis tab. P066 puts the muscle views here; progress charts (P068) and insights (P069) come next.
struct AnalysisRootView: View {
    let router: TabRouter<AnalysisRoute>
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: MuscleAnalysisModel?
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
        .navigationTitle("shell.tabbar.analysis")
        .task { await prepare() }
        .task(id: container.historyEvents.version) { await model?.load() }
        .accessibilityIdentifier("analysis-root")
    }

    private func content(_ model: MuscleAnalysisModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader("muscles.title", subtitle: "muscles.subtitle")
                Picker("muscles.mode", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                    Text("muscles.mode.score").tag(MuscleAnalysisModel.Mode.score)
                    Text("muscles.mode.load").tag(MuscleAnalysisModel.Mode.load)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("muscle-mode-picker")
                mapCard(model)
                if model.mode == .score, let reason = model.unavailable { unavailableCard(reason) }
                legend(model)
                list(model)
            }
            .padding(Spacing.md)
        }
    }

    // MARK: Map

    private func mapCard(_ model: MuscleAnalysisModel) -> some View {
        Card {
            MuscleMapView(intensities: model.intensities, style: .default) { muscle in
                router.push(.muscle(muscle.rawValue))
            }
            .frame(maxWidth: .infinity)
            // The list below carries the same information for VoiceOver (P066): the map is decoration there.
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("muscle-map")
    }

    private func legend(_ model: MuscleAnalysisModel) -> some View {
        Group {
            switch model.mode {
            case .score: Text(model.hasScores ? "muscles.legend.score" : "muscles.empty.score")
            case .load: Text(model.hasLoad ? "muscles.legend.load" : "muscles.empty.load")
            }
        }
        .font(DSFont.footnote)
        .foregroundStyle(DSColor.textSecondary)
    }

    private func unavailableCard(_ reason: ScoreUnavailable) -> some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                Text(reason == .noBodyweight ? "muscles.unavailable.weight" : "muscles.unavailable.profile")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    // MARK: List

    private func list(_ model: MuscleAnalysisModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(model.listRows) { row in
                NavigationLink(value: AnalysisRoute.muscle(row.muscle.rawValue)) {
                    MuscleRowView(row: row, mode: model.mode, locale: locale)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("muscle-row-\(row.muscle.rawValue)")
            }
        }
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeMuscleAnalysisModel() else {
            failed = true
            return
        }
        model = created
        await created.load()
    }
}

/// One muscle in the list: name, score or sets, change and the "weakest" / "not trained" flags.
struct MuscleRowView: View {
    let row: MuscleAnalysisModel.Row
    let mode: MuscleAnalysisModel.Mode
    let locale: Locale

    var body: some View {
        Card(padding: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: row.muscle.localizedName(locale: locale)).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    flags
                }
                Spacer(minLength: Spacing.sm)
                value
                Image(systemName: "chevron.right").font(DSFont.caption).foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: HitTarget.minimum - Spacing.md)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var flags: some View {
        switch mode {
        case .score:
            if row.isWeak { TagChip("muscles.weak", systemImage: "arrow.down.right", style: .warning) }
            else if row.score == nil { Text("muscles.noScore").font(DSFont.caption).foregroundStyle(DSColor.textTertiary) }
        case .load:
            if row.sets == 0 { TagChip("muscles.neglected", systemImage: "exclamationmark.triangle", style: .warning) }
        }
    }

    @ViewBuilder private var value: some View {
        switch mode {
        case .score:
            if let score = row.score {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(verbatim: "\(Int(score.rounded()))").font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
                    ChangeLabel(change: row.change)
                }
            }
        case .load:
            Text("muscles.sets \(MuscleFormat.sets(row.sets, locale: locale))").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
        }
    }
}

enum MuscleFormat {
    /// "12" or "7,5": at most one decimal.
    static func sets(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}

/// "+3" / "−2" over four weeks; nothing when unknown.
struct ChangeLabel: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.5 {
            let rounded = Int(change.rounded())
            Label {
                Text(verbatim: rounded > 0 ? "+\(rounded)" : "\(rounded)")
            } icon: {
                Image(systemName: rounded > 0 ? "arrow.up.right" : "arrow.down.right")
            }
            .font(DSFont.caption)
            .foregroundStyle(rounded > 0 ? DSColor.success : DSColor.textSecondary)
            .labelStyle(.titleAndIcon)
        }
    }
}
