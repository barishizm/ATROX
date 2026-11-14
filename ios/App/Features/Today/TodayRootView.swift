import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// The Today tab, the app's home screen (P067).
struct TodayRootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ActiveWorkoutPresenter.self) private var presenter
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: TodayModel?
    @State private var failed = false
    @State private var actions = InsightActions()
    @State private var openedExercise: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if failed {
                ErrorState(message: "today.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("shell.tabbar.today")
        .howItWorksButton()
        .task { await prepare() }
        .task(id: container.historyEvents.version) { await model?.load() }
        .sheet(item: $actions.sheet) { sheet in
            InsightSuggestionsSheet(sheet: sheet) { id in
                actions.sheet = nil
                openedExercise = id
            }
        }
        .navigationDestination(item: $openedExercise) { id in ExerciseDetailView(exerciseID: id) }
        .accessibilityIdentifier("today-root")
    }

    @ViewBuilder
    private func insightCard(_ model: TodayModel) -> some View {
        if let item = model.insight {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("insight.today.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
                InsightCardView(
                    item: item,
                    onAction: { Task { await actions.perform(item, container: container) { openedExercise = $0 } } },
                    onDismiss: { Task { await model.dismissInsight() } }
                )
            }
            .accessibilityIdentifier("today-insight")
        }
    }

    private var weeklyLink: some View {
        NavigationLink(value: TodayRoute.weeklySummary) {
            Card {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                    Text("weekly.link").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(DSFont.caption).foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-weekly-link")
    }

    @ViewBuilder
    private func content(_ model: TodayModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else if model.isNewUser && model.overall == nil {
            newUser(model)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    scoreCard(model)
                    insightCard(model)
                    weeklyLink
                    if model.showsBodyweightReminder && model.insight?.insight.kind != .bodyweightStale { reminderCard }
                    if !model.bars.isEmpty { patternSection(model) }
                    planCard(model)
                    weekSection(model)
                    highlights(model)
                }
                .padding(Spacing.md)
            }
        }
    }

    // MARK: New user

    private func newUser(_ model: TodayModel) -> some View {
        EmptyState(
            systemImage: "dumbbell", title: "today.new.title", message: "today.new.message", actionTitle: "today.new.action"
        ) {
            Task { await startToday(model) }
        }
        .accessibilityIdentifier("today-new-user")
    }

    private func startToday(_ model: TodayModel) async {
        if case .planned(let day) = model.plan {
            await presenter.start(routineId: day.routineId, dayId: day.dayId, container: container)
        } else {
            await presenter.startEmpty(container: container)
        }
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
        default: "today.score.none"
        }
    }

    private var reminderCard: some View {
        Card {
            Label("today.reminder.weight", systemImage: "scalemass").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        }
    }

    // MARK: Patterns

    private func patternSection(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("today.patterns").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            Card {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.bars) { bar in PatternBarRow(bar: bar) }
                }
            }
            .accessibilityIdentifier("today-patterns")
        }
    }

    // MARK: Workout

    @ViewBuilder
    private func planCard(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("today.workout.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    planContent(model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("today-workout-card")
        }
    }

    @ViewBuilder
    private func planContent(_ model: TodayModel) -> some View {
        if presenter.hasActiveWorkout {
            Text("today.workout.active").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            PrimaryButton("workout.continue") { presenter.resume() }
        } else {
            switch model.plan {
            case .planned(let day):
                Text(verbatim: day.dayName).font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                Text("today.workout.detail \(day.routineName) \(day.exerciseCount)").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                if model.facts?.trainedToday == true {
                    Label("today.workout.doneToday", systemImage: "checkmark.circle").font(DSFont.callout).foregroundStyle(DSColor.success)
                }
                PrimaryButton("today.workout.start") { Task { await presenter.start(routineId: day.routineId, dayId: day.dayId, container: container) } }
                    .accessibilityIdentifier("today-start-workout")
            case .suggestion(let name):
                Text("today.workout.noProgram").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                Text("today.workout.suggestion \(name)").font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                NavigationLink(value: TodayRoute.templates) { Text("today.workout.templates") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("today-open-templates")
            case .none:
                Text("today.workout.noProgram").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                PrimaryButton("today.new.action") { Task { await presenter.startEmpty(container: container) } }
            }
        }
    }

    // MARK: Week

    private func weekSection(_ model: TodayModel) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md)) : AnyLayout(HStackLayout(spacing: Spacing.md))
        return layout {
            Card {
                HStack(spacing: Spacing.md) {
                    GoalRing(done: model.weeklyDone, goal: model.weeklyGoal)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("today.week.title").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        Text("today.week.count \(model.weeklyDone) \(model.weeklyGoal)").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-week-goal")
            Card {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "flame.fill").foregroundStyle(model.streakWeeks > 0 ? DSColor.accent : DSColor.textTertiary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("today.streak.title").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        Text("today.streak.weeks \(model.streakWeeks)").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-streak")
        }
    }

    // MARK: Highlights

    @ViewBuilder
    private func highlights(_ model: TodayModel) -> some View {
        if model.record != nil || model.improved != nil {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("today.highlights").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
                if let record = model.record {
                    NavigationLink(value: TodayRoute.exerciseScore(catalogId: record.exerciseId)) {
                        highlightCard(icon: "trophy", title: "today.highlights.record") {
                            Text(verbatim: record.name).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                            HStack(spacing: Spacing.xs) {
                                Text(LocalizedStringKey.dynamic("today.record.kind.\(record.kind.rawValue)"))
                                Text(verbatim: "· \(record.valueText)")
                            }
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                            Text(verbatim: record.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                                .font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("today-highlight-record")
                }
                if let improved = model.improved {
                    NavigationLink(value: TodayRoute.exerciseScore(catalogId: improved.exerciseId)) {
                        highlightCard(icon: "arrow.up.right.circle", title: "today.highlights.improved") {
                            Text(verbatim: improved.name).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                            Text("today.highlights.improved.change \(improved.change)").font(DSFont.callout).foregroundStyle(DSColor.success)
                        }
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("today-highlight-improved")
                }
            }
        }
    }

    private func highlightCard<Body: View>(icon: String, title: LocalizedStringKey, @ViewBuilder body: () -> Body) -> some View {
        Card(padding: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: icon).foregroundStyle(DSColor.accent).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title).font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
                    body()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(DSFont.caption).foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let created = await container.makeTodayModel() else {
            failed = true
            return
        }
        model = created
        await created.load()
    }
}

/// One movement pattern: name, bar and score (or a dash while the pattern is open).
struct PatternBarRow: View {
    let bar: TodayModel.PatternBar

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(LocalizedStringKey.dynamic("today.pattern.\(bar.pattern)")).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColor.surfaceOverlay)
                    if let score = bar.score {
                        Capsule().fill(DSColor.accent).frame(width: max(6, proxy.size.width * min(max(score, 0), 100) / 100))
                    }
                }
            }
            .frame(width: 96, height: 8)
            .accessibilityHidden(true)
            Text(verbatim: bar.score.map { "\(Int($0.rounded()))" } ?? "–")
                .font(DSFont.numericSmall).foregroundStyle(bar.score == nil ? DSColor.textTertiary : DSColor.textPrimary)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey.dynamic("today.pattern.\(bar.pattern)")))
        .accessibilityValue(bar.score.map { Text(verbatim: "\(Int($0.rounded()))") } ?? Text("today.pattern.open"))
    }
}

/// Ring of this week's workouts against the goal.
struct GoalRing: View {
    let done: Int
    let goal: Int

    var body: some View {
        let progress = goal > 0 ? min(Double(done) / Double(goal), 1) : 0
        ZStack {
            Circle().stroke(DSColor.surfaceOverlay, lineWidth: 8)
            Circle().trim(from: 0, to: progress).stroke(DSColor.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(verbatim: "\(done)").font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}
