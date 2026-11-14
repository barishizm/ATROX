import Charts
import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// Full-screen exercise score (P065): ring + sentence, "where you are in the distribution", group switcher, confidence
/// with reasons, next-level target and the set behind the score.
struct ExerciseScoreView: View {
    let exerciseID: String
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: ExerciseScoreModel?
    @State private var center: ScoreCenter?
    @State private var unavailable = false
    @State private var showsReasons = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if unavailable {
                ErrorState(message: "scorescreen.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("scorescreen.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { ShareCardButton(content: model?.shareContent).labelStyle(.iconOnly) } }
        .howItWorksButton()
        .task { await prepare() }
        .accessibilityIdentifier("exercise-score-root")
    }

    @ViewBuilder
    private func content(_ model: ExerciseScoreModel) -> some View {
        switch model.state {
        case .loading: LoadingState()
        case .failed: ErrorState(message: "scorescreen.error") { Task { await model.load() } }
        case .unavailable(let reason): unavailableState(reason)
        case .ready(let insight): ready(model, insight)
        }
    }

    // MARK: Ready

    private func ready(_ model: ExerciseScoreModel, _ insight: ExerciseInsight) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !model.name.isEmpty {
                    Text(verbatim: model.name).font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                groupPicker(model)
                if let notice = center?.modelChange { modelChangeCard(notice) }
                if let score = model.score {
                    hero(model, score: score)
                    if insight.distribution != nil { distributionSection(model) }
                    confidenceSection(model)
                    if let target = model.target { targetSection(target) } else if model.percentile != nil { topLevelNote }
                    if let basis = model.basisText { basisSection(basis) }
                    if center?.showsBodyweightReminder == true { bodyweightCard }
                } else {
                    emptyState(insight)
                }
            }
            .padding(Spacing.md)
        }
    }

    private func groupPicker(_ model: ExerciseScoreModel) -> some View {
        Picker("scorescreen.group", selection: Binding(get: { model.population }, set: { group in Task { await model.select(group) } })) {
            Text("scorescreen.group.gym").tag(ReferencePopulation.gym)
            Text("scorescreen.group.general").tag(ReferencePopulation.general)
            Text("scorescreen.group.competitor").tag(ReferencePopulation.competitor)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("score-group-picker")
    }

    private func hero(_ model: ExerciseScoreModel, score: Double) -> some View {
        VStack(spacing: Spacing.md) {
            ScoreRing(score: score)
                .frame(maxWidth: .infinity)
            if let percentile = model.percentile {
                sentence(model, percentile: percentile)
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("score-sentence")
            }
        }
    }

    @ViewBuilder
    private func sentence(_ model: ExerciseScoreModel, percentile: Int) -> some View {
        let suffix = model.sentenceSuffix
        switch model.sentenceKey {
        case "general": Text("scorescreen.sentence.general \(percentile) \(suffix)")
        case "competitor": Text("scorescreen.sentence.competitor \(percentile) \(suffix)")
        default: Text("scorescreen.sentence.gym \(percentile) \(suffix)")
        }
    }

    // MARK: Distribution chart

    private func distributionSection(_ model: ExerciseScoreModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("scorescreen.distribution").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ScoreDistributionChart(model: model).frame(height: 190)
                    Text("scorescreen.distribution.axis \(model.axisUnit)")
                        .font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("scorescreen.distribution.a11y"))
            .accessibilityIdentifier("score-distribution")
        }
    }

    // MARK: Confidence

    private func confidenceSection(_ model: ExerciseScoreModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                showsReasons.toggle()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.seal").accessibilityHidden(true)
                    Text(LocalizedStringKey("scorescreen.confidence.\(model.confidence?.rawValue ?? "low")"))
                    Spacer()
                    if !model.reasons.isEmpty {
                        Image(systemName: showsReasons ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                    }
                }
                .font(DSFont.callout.weight(.semibold))
                .foregroundStyle(confidenceColor(model.confidence))
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.reasons.isEmpty)
            .accessibilityIdentifier("score-confidence")
            if showsReasons {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(model.reasons, id: \.self) { reason in
                        Label(LocalizedStringKey("scorescreen.reason.\(reason.rawValue)"), systemImage: "info.circle")
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .accessibilityIdentifier("score-confidence-reasons")
            }
        }
    }

    private func confidenceColor(_ confidence: ScoreConfidence?) -> Color {
        switch confidence {
        case .high: DSColor.success
        case .medium: DSColor.warning
        default: DSColor.textSecondary
        }
    }

    // MARK: Next level, basis

    private func targetSection(_ target: ExerciseScoreModel.Target) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("scorescreen.next").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("scorescreen.next.level \(target.level.localizedName(locale: locale)) \(target.minScore)")
                        .font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                    Text("scorescreen.next.e1rm \(target.e1rmText) \(target.gapText)")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    Text("scorescreen.next.loads").dsOverline()
                    HStack(spacing: Spacing.sm) {
                        ForEach(target.loads, id: \.self) { load in
                            Text(verbatim: load).font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                                .background(DSColor.surfaceRaised, in: Capsule())
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("score-next-level")
        }
    }

    private var topLevelNote: some View {
        Card { Text("scorescreen.next.top").font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
    }

    private func basisSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("scorescreen.basis").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Card { Text(verbatim: text).font(DSFont.callout).foregroundStyle(DSColor.textPrimary) }
                .accessibilityIdentifier("score-basis")
        }
    }

    // MARK: Cards

    private func modelChangeCard(_ change: ModelUpdater.Change) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("scorescreen.modelchange.title", systemImage: "arrow.triangle.2.circlepath")
                    .font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                Text("scorescreen.modelchange.message \(change.from) \(change.to)")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                Button("scorescreen.modelchange.ok") { center?.acknowledgeModelChange() }
                    .font(DSFont.callout.weight(.semibold))
            }
        }
        .accessibilityIdentifier("score-model-change")
    }

    private var bodyweightCard: some View {
        Card {
            Label("scorescreen.bodyweight.reminder", systemImage: "scalemass")
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        }
        .accessibilityIdentifier("score-bodyweight-reminder")
    }

    // MARK: Empty

    private func emptyState(_ insight: ExerciseInsight) -> some View {
        let key: String = switch insight.notScorable {
        case .notInModel: "notInModel"
        case .noStrength: "noStrength"
        default: "noData"
        }
        return EmptyState(
            systemImage: "chart.bar.xaxis", title: LocalizedStringKey("scorescreen.empty.\(key).title"),
            message: LocalizedStringKey("scorescreen.empty.\(key).message")
        )
        .accessibilityIdentifier("score-empty")
    }

    private func unavailableState(_ reason: ScoreUnavailable) -> some View {
        let key: String = switch reason {
        case .noProfile: "noProfile"
        case .noBodyweight: "noBodyweight"
        case .noModel: "noModel"
        }
        return EmptyState(
            systemImage: "person.crop.circle.badge.questionmark", title: LocalizedStringKey("scorescreen.unavailable.\(key).title"),
            message: LocalizedStringKey("scorescreen.unavailable.\(key).message")
        )
    }

    // MARK: Loading

    private func prepare() async {
        guard model == nil else { return }
        guard let context = await container.makeHistoryContext(), let service = container.scoreService else {
            unavailable = true
            return
        }
        let userId = context.userId
        let id = exerciseID
        let created = ExerciseScoreModel(
            exerciseID: id, userId: userId, service: service, population: await service.preferredPopulation(userId: userId),
            unit: context.unit, locale: context.locale, languageCode: context.languageCode,
            name: { await context.loadNames()[id] ?? "" }
        )
        center = await container.scoreCenter()
        model = created
        await created.load()
    }
}

/// The population density over e1RM with the user's position, median, level thresholds and uncertainty band.
struct ScoreDistributionChart: View {
    let model: ExerciseScoreModel
    @Environment(\.locale) private var locale

    var body: some View {
        Chart {
            if let band = model.bandX {
                RectangleMark(xStart: .value("low", band.lowerBound), xEnd: .value("high", band.upperBound))
                    .foregroundStyle(DSColor.accent.opacity(0.16))
            }
            ForEach(model.densityPoints) { point in
                AreaMark(x: .value("e1RM", point.x), y: .value("density", point.y))
                    .foregroundStyle(LinearGradient(colors: [DSColor.accent.opacity(0.35), DSColor.accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("e1RM", point.x), y: .value("density", point.y))
                    .foregroundStyle(DSColor.accent)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(model.levelMarkers) { marker in
                RuleMark(x: .value("level", marker.x))
                    .foregroundStyle(DSColor.level(marker.level).opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text(verbatim: marker.level.localizedName(locale: locale).prefix(3).uppercased())
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(DSColor.textTertiary)
                    }
            }
            if let median = model.medianX {
                RuleMark(x: .value("median", median))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .bottom, alignment: .center, spacing: 2) {
                        Text("scorescreen.distribution.median").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DSColor.textSecondary)
                    }
            }
            if let user = model.userX {
                RuleMark(x: .value("you", user))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .annotation(position: .overlay, alignment: .topLeading, spacing: 4) {
                        Text("scorescreen.distribution.you").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DSColor.onAccent).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DSColor.accent, in: Capsule())
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel() } }
    }
}
