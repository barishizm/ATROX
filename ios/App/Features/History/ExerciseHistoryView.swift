import Charts
import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// One exercise across all workouts (P042): best sets, an e1RM line chart, standing records and every session.
struct ExerciseHistoryView: View {
    let exerciseID: String
    @Environment(AppContainer.self) private var container
    @State private var model: ExerciseHistoryModel?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if unavailable {
                ErrorState(message: "history.error") { Task { await prepare() } }
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle(model?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .accessibilityIdentifier("exercise-history-root")
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let context = await container.makeHistoryContext() else {
            unavailable = true
            return
        }
        unavailable = false
        let created = ExerciseHistoryModel(ref: ActiveWorkoutView.ref(exerciseID), context: context)
        model = created
        await created.load()
    }

    @ViewBuilder
    private func content(_ model: ExerciseHistoryModel) -> some View {
        if model.isLoading {
            LoadingState()
        } else if model.failed {
            ErrorState(message: "history.error") { Task { await model.load() } }
        } else if model.isEmpty {
            EmptyState(systemImage: "chart.xyaxis.line", title: "exercisehistory.empty.title", message: "exercisehistory.empty.message")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ExerciseStatsGrid(model: model)
                    chartCard(model)
                    sessionsSection(model)
                }
                .padding(Spacing.md)
            }
        }
    }

    private func chartCard(_ model: ExerciseHistoryModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("exercisehistory.chart", subtitle: "exercisehistory.chart.subtitle")
            Card {
                if model.chartPoints.count < 2 {
                    Text("exercisehistory.chart.few").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                } else {
                    Chart(model.chartPoints) { point in
                        LineMark(x: .value("Date", point.date), y: .value("e1RM", point.value))
                            .foregroundStyle(DSColor.accent)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value("e1RM", point.value))
                            .foregroundStyle(DSColor.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel(model.context.unit.symbol)
                    .frame(height: 200)
                    .accessibilityLabel("exercisehistory.chart.label")
                    .accessibilityIdentifier("exercise-e1rm-chart")
                }
            }
        }
    }

    private func sessionsSection(_ model: ExerciseHistoryModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("exercisehistory.sessions")
            Card(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(model.sessions, id: \.workoutId) { session in
                        NavigationLink(value: WorkoutRoute.workoutDetail(id: session.workoutId)) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(session.date, format: .dateTime.day().month(.abbreviated).year()).font(DSFont.headline)
                                Text(verbatim: model.setsText(of: session)).font(DSFont.callout)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier("exercise-sessions")
    }
}

/// Heaviest set, best e1RM, last trained, session count and the standing records.
struct ExerciseStatsGrid: View {
    let model: ExerciseHistoryModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            StatTile("exercise.detail.bestSet", value: model.heaviestText ?? "—")
            StatTile("exercise.detail.e1rm", value: model.bestE1rmText ?? "—")
            StatTile(
                "exercise.detail.lastPerformed",
                value: model.progress.lastDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "—"
            )
            StatTile("exercisehistory.sessions", value: "\(model.progress.sessionCount)")
            if let volume = model.recordText(.volume) { StatTile("workout.record.volume", value: volume) }
            if let weight = model.recordText(.weight) { StatTile("workout.record.weight", value: weight) }
        }
        .accessibilityIdentifier("exercise-stats")
    }
}
