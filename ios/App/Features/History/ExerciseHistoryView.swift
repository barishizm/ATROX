import Charts
import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// One exercise across all workouts: a Weight / Volume Load / Estimated 1RM chart with a range switch, "Add Set",
/// and every session as a dated list of sets.
struct ExerciseHistoryView: View {
    let exerciseID: String
    /// False inside a running workout, where a logged set would land in a different, finished workout.
    var allowsLogging = true
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var model: ExerciseHistoryModel?
    @State private var unavailable = false
    @State private var adding = false

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
        .sheet(isPresented: $adding) {
            if let model { AddSetSheet(model: model) { container.historyEvents.changed() } }
        }
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
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !model.isEmpty {
                        tabs(model)
                        summary(model)
                        chart(model)
                        rangePicker(model)
                    }
                    if allowsLogging { addSetButton }
                    if model.isEmpty {
                        Text("exercisehistory.empty.message")
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, Spacing.md)
                    } else {
                        sessionsSection(model)
                    }
                }
            }
        }
    }

    // MARK: Tabs, numbers, chart

    private func tabs(_ model: ExerciseHistoryModel) -> some View {
        HStack(spacing: 0) {
            ForEach(ProgressMetric.allCases) { metric in
                let selected = model.metric == metric
                Button { withAnimation(.easeInOut(duration: 0.2)) { model.metric = metric } } label: {
                    VStack(spacing: Spacing.sm) {
                        Text(title(of: metric))
                            .font(selected ? DSFont.headline : DSFont.callout.weight(.semibold))
                            .foregroundStyle(selected ? DSColor.textPrimary : DSColor.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum - Spacing.sm)
                        Rectangle().fill(selected ? DSColor.accent : DSColor.separator)
                            .frame(height: selected ? 3 : 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("exercise-metric-\(metric)")
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func title(of metric: ProgressMetric) -> LocalizedStringKey {
        switch metric {
        case .weight: "exprogress.tab.weight"
        case .volume: "exprogress.tab.volume"
        case .e1rm: "exprogress.tab.e1rm"
        }
    }

    private func descriptorTitle(of metric: ProgressMetric) -> String {
        switch metric {
        case .weight: String(localized: "exprogress.tab.weight", locale: locale)
        case .volume: String(localized: "exprogress.tab.volume", locale: locale)
        case .e1rm: String(localized: "exprogress.tab.e1rm", locale: locale)
        }
    }

    private func summary(_ model: ExerciseHistoryModel) -> some View {
        let unit = model.metric == .volume ? "" : model.context.unit.symbol
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                figure("exprogress.current", value: model.currentValue, unit: unit, signed: false)
                figure("exprogress.difference", value: model.difference, unit: unit, signed: true)
            }
            if let dates = model.windowDates {
                Text("\(dates.from.formatted(.dateTime.day().month(.abbreviated))) – \(dates.to.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: LocalizedStringKey, value: Double?, unit: String, signed: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(verbatim: value.map { Self.number($0, signed: signed, locale: locale) } ?? "—")
                    .font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                if value != nil, !unit.isEmpty {
                    Text(verbatim: unit).font(DSFont.headline).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }

    static func number(_ value: Double, signed: Bool, locale: Locale) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(0...1))
        let text = value.formatted(style)
        return signed && value > 0 ? "+" + text : text
    }

    @ViewBuilder
    private func chart(_ model: ExerciseHistoryModel) -> some View {
        let points = model.visiblePoints
        if points.count < 2 {
            Text("exprogress.chart.few")
                .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .padding(.horizontal, Spacing.md)
        } else {
            Chart(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(LinearGradient(
                        colors: [DSColor.accent.opacity(0.55), DSColor.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(DSColor.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(DSColor.accent)
                    .symbolSize(points.count > 14 ? 0 : 40)
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: 260)
            .padding(.horizontal, Spacing.md)
            .accessibilityLabel(title(of: model.metric))
            .dsChartDescriptor(ChartAccessibility.descriptor(
                title: descriptorTitle(of: model.metric),
                points: points.map { ChartSeriesPoint(date: $0.date, value: $0.value) },
                yTitle: descriptorTitle(of: model.metric),
                unit: model.metric == .volume ? "" : model.context.unit.symbol, locale: locale))
            .accessibilityIdentifier("exercise-e1rm-chart")
        }
    }

    private func rangePicker(_ model: ExerciseHistoryModel) -> some View {
        Picker("progress.range", selection: Bindable(model).range) {
            ForEach(ProgressRange.allCases) { range in
                Text(label(of: range)).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(Spacing.md)
        .accessibilityIdentifier("exercise-range")
    }

    private func label(of range: ProgressRange) -> LocalizedStringKey {
        switch range {
        case .month: "exprogress.range.month"
        case .quarter: "exprogress.range.quarter"
        case .all: "exprogress.range.all"
        }
    }

    // MARK: Add set, sessions

    private var addSetButton: some View {
        Button { adding = true } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "plus").font(.title3.weight(.medium))
                Text("exprogress.addSet").font(DSFont.headline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: HitTarget.minimum + Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise-add-set")
    }

    private func sessionsSection(_ model: ExerciseHistoryModel) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.sessions, id: \.workoutId) { session in
                NavigationLink(value: WorkoutRoute.workoutDetail(id: session.workoutId)) {
                    Text(session.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                        .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.md)
                let sets = model.visibleSets(of: session)
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    setRow(set, session: session, model: model)
                    if index < sets.count - 1 { Divider().overlay(DSColor.separator).padding(.horizontal, Spacing.md) }
                }
            }
        }
        .padding(.bottom, Spacing.xl)
        .accessibilityIdentifier("exercise-sessions")
    }

    private func setRow(_ set: SetSnapshot, session: ExerciseSession, model: ExerciseHistoryModel) -> some View {
        HStack(spacing: Spacing.sm) {
            if let tag = set.input.tag { Circle().fill(tag.color).frame(width: 10, height: 10).accessibilityHidden(true) }
            Text(verbatim: model.setLine(set, locale: locale))
                .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            if let time = set.updatedAt, Calendar.current.isDate(time, inSameDayAs: session.date) {
                Text(time, format: .dateTime.hour().minute())
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: HitTarget.minimum)
        .accessibilityElement(children: .combine)
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
