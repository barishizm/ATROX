import DataKit
import DesignSystem
import SwiftUI

/// History tab section (P042): a month calendar with totals above the chronological list of finished workouts.
struct HistoryView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: HistoryModel?
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
        .navigationTitle("history.title")
        .task { await prepare() }
        .accessibilityIdentifier("history-root")
    }

    private func prepare() async {
        guard model == nil else { return }
        guard let context = await container.makeHistoryContext() else {
            unavailable = true
            return
        }
        unavailable = false
        let created = HistoryModel(context: context, events: container.historyEvents)
        model = created
        await created.load()
    }

    @ViewBuilder
    private func content(_ model: HistoryModel) -> some View {
        List {
            Section { calendarCard(model) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if model.workouts.isEmpty, model.didLoad {
                Section {
                    EmptyState(systemImage: "calendar", title: "history.empty.title", message: "history.empty.message")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("history.list") {
                    ForEach(model.workouts) { workout in
                        NavigationLink(value: WorkoutRoute.workoutDetail(id: workout.id)) { row(workout, model: model) }
                            .task { await model.loadMoreIfNeeded(current: workout) }
                            .swipeActions {
                                Button("history.delete", role: .destructive) {
                                    Task { await model.delete(workout, title: model.title(of: workout, fallback: defaultTitle)) }
                                }
                            }
                    }
                    if model.hasMore { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) { undoBanner(model) }
        .task(id: container.historyEvents.version) { if model.didLoad { await model.refresh() } }
        .accessibilityIdentifier("history-list")
    }

    private var defaultTitle: String { String(localized: "workout.title.default") }

    private func calendarCard(_ model: HistoryModel) -> some View {
        Card {
            VStack(spacing: Spacing.sm) {
                HStack {
                    Button { Task { await model.shiftMonth(by: -1) } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("history.month.previous")
                        .accessibilityIdentifier("history-month-previous")
                    Spacer()
                    Text(model.month, format: .dateTime.month(.wide).year()).font(DSFont.headline)
                    Spacer()
                    Button { Task { await model.shiftMonth(by: 1) } } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canShowNextMonth)
                        .accessibilityLabel("history.month.next")
                        .accessibilityIdentifier("history-month-next")
                }
                MonthCalendarView(month: model.month, trainedDays: model.monthSummary.trainedDays, calendar: model.calendar)
                Divider()
                monthTotals(model)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    private func monthTotals(_ model: HistoryModel) -> some View {
        let summary = model.monthSummary
        return HStack {
            totalCell("history.month.workouts", value: "\(summary.workoutCount)")
            totalCell("history.month.time", value: HistoryContext.durationText(summary.totalDuration))
            totalCell("history.month.volume", value: model.context.weightText(summary.totalVolumeKg))
        }
        .accessibilityIdentifier("history-month-totals")
    }

    private func totalCell(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(title).dsOverline()
            Text(verbatim: value).font(DSFont.numericSmall).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ workout: WorkoutSnapshot, model: HistoryModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(verbatim: model.title(of: workout, fallback: defaultTitle)).font(DSFont.headline)
                Spacer()
                Text(workout.startedAt, format: .dateTime.day().month(.abbreviated))
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
            Text(verbatim: model.exerciseNames(of: workout)).font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary).lineLimit(2)
            Text(verbatim: "\(HistoryContext.durationText(workout.duration ?? 0)) · \(model.volumeText(of: workout))")
                .font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-row")
    }

    @ViewBuilder
    private func undoBanner(_ model: HistoryModel) -> some View {
        if let pending = container.historyEvents.undo {
            HStack {
                Text("history.deleted \(pending.title)").font(DSFont.callout).lineLimit(1)
                Spacer()
                Button("history.undo") { Task { await model.undoDelete() } }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("history-undo")
            }
            .padding(Spacing.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: pending.id) {
                try? await Task.sleep(for: .seconds(8))
                if container.historyEvents.undo?.id == pending.id { container.historyEvents.undo = nil }
            }
        }
    }
}
