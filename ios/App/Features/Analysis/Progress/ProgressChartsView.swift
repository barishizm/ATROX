import Charts
import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// The "Progress" section of the Analysis tab (P068): range picker, then one card per chart.
struct ProgressChartsView: View {
    let model: ProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Picker("progress.range", selection: Binding(get: { model.range }, set: { model.range = $0 })) {
                ForEach(ChartRange.allCases) { range in Text(LocalizedStringKey.dynamic("progress.range.\(range.rawValue)")).tag(range) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("progress-range-picker")
            if model.hasData {
                E1RMCard(model: model)
                PaceCard(model: model)
                ScoreSeriesCard(model: model)
                VolumeCard(model: model)
                FrequencyCard(model: model)
                BodyweightCard(model: model)
            } else {
                Card {
                    Text(model.unavailable == nil ? "progress.empty" : "progress.unavailable")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityIdentifier("progress-empty")
            }
        }
    }
}

// MARK: - Shared pieces

private struct ChartCard<Content: View, Header: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    header
                    content
                }
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

/// What the finger is on (or the latest value): big number plus caption.
private struct Readout: View {
    let value: String
    let caption: String
    var note: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: value).font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
            Text(verbatim: caption).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            if let note { Text(note).font(DSFont.caption).foregroundStyle(DSColor.success) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyChartText: View {
    let key: LocalizedStringKey
    var body: some View {
        Text(key).font(DSFont.callout).foregroundStyle(DSColor.textSecondary).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }
}

// MARK: - e1RM

private struct E1RMCard: View {
    let model: ProgressModel
    @Environment(AppContainer.self) private var container
    @State private var selection: Date?

    private struct Row: Identifiable {
        let date: Date
        let mid: Double
        let low: Double
        let high: Double
        var id: Date { date }
    }

    var body: some View {
        ChartCard(title: "progress.e1rm.title", identifier: "progress-e1rm") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("progress.exercise", selection: Binding(get: { model.exerciseId ?? "" }, set: { model.exerciseId = $0 })) {
                    ForEach(model.exercises) { option in Text(verbatim: option.name).tag(option.id) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("progress-exercise-picker")
                readout
            }
        } content: {
            if model.e1rmPoints.count >= 2 {
                chart
                legend
                if isLocked && hasProContent { LockedFeatureCard(feature: .forecast) }
            } else {
                EmptyChartText(key: "progress.e1rm.empty")
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let point = selectedPoint ?? model.e1rmPoints.last {
            Readout(value: model.weightText(point.e1rmKg), caption: model.dateText(point.date), note: point.isRecord ? "progress.record" : nil)
        }
    }

    private var selectedPoint: ProgressPoint? {
        selection.flatMap { ProgressModel.nearest(model.e1rmPoints, to: $0, at: \.date) }
    }

    /// Forecast and plateau analysis are Pro (P091); the e1RM line, trend and records stay free.
    private var isLocked: Bool { FeatureGate.isLocked(.forecast, isPro: container.purchases.isPro) }

    private var hasProContent: Bool { model.progress?.forecast.isEmpty == false || !model.plateauZones.isEmpty }

    private var forecastRows: [Row] {
        guard !isLocked, let last = model.e1rmPoints.last, let progress = model.progress, !progress.forecast.isEmpty else { return [] }
        let anchor = Row(date: last.date, mid: last.e1rmKg, low: last.e1rmKg, high: last.e1rmKg)
        return [anchor] + progress.forecast.map { Row(date: $0.date, mid: $0.e1rmKg, low: $0.low, high: $0.high) }
    }

    private var xDomain: ClosedRange<Date> {
        let start = model.rangeStartDate ?? model.e1rmPoints.first?.date ?? Date()
        let end = max(forecastRows.last?.date ?? .distantPast, model.e1rmPoints.last?.date ?? Date())
        return start...max(end, start.addingTimeInterval(86_400))
    }

    private var chart: some View {
        Chart {
            ForEach(Array((isLocked ? [] : model.plateauZones).enumerated()), id: \.offset) { _, zone in
                RectangleMark(
                    xStart: .value("start", ScoreCalculator.date(ofDay: zone.startDay)), xEnd: .value("end", ScoreCalculator.date(ofDay: zone.endDay))
                )
                .foregroundStyle(DSColor.warning.opacity(0.14))
            }
            ForEach(forecastRows) { row in
                AreaMark(x: .value("date", row.date), yStart: .value("low", model.displayWeight(row.low)), yEnd: .value("high", model.displayWeight(row.high)), series: .value("s", "band"))
                    .foregroundStyle(DSColor.accent.opacity(0.18))
                LineMark(x: .value("date", row.date), y: .value("e1RM", model.displayWeight(row.mid)), series: .value("s", "forecast"))
                    .foregroundStyle(DSColor.accent.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4]))
            }
            ForEach(model.progress?.trendLine ?? []) { point in
                LineMark(x: .value("date", point.date), y: .value("e1RM", model.displayWeight(point.e1rmKg)), series: .value("s", "trend"))
                    .foregroundStyle(DSColor.textSecondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            ForEach(model.e1rmPoints) { point in
                LineMark(x: .value("date", point.date), y: .value("e1RM", model.displayWeight(point.e1rmKg)), series: .value("s", "sessions"))
                    .foregroundStyle(DSColor.accent).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("date", point.date), y: .value("e1RM", model.displayWeight(point.e1rmKg)))
                    .foregroundStyle(point.isRecord ? DSColor.success : DSColor.accent).symbolSize(point.isRecord ? 70 : 24)
            }
            if let point = selectedPoint {
                RuleMark(x: .value("date", point.date)).foregroundStyle(DSColor.textTertiary).lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(model.unit.symbol, position: .topLeading)
        .chartXSelection(value: $selection)
        .frame(height: 230)
        .accessibilityLabel(Text("progress.e1rm.title"))
        .accessibilityValue(Text(verbatim: model.e1rmPoints.last.map { model.weightText($0.e1rmKg) } ?? ""))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label("progress.legend.record", systemImage: "circle.fill").foregroundStyle(DSColor.success)
            if !isLocked, !model.plateauZones.isEmpty { Label("progress.legend.plateau", systemImage: "square.fill").foregroundStyle(DSColor.warning) }
            if !isLocked, model.progress?.forecast.isEmpty == false { Label("progress.legend.forecast", systemImage: "ellipsis").foregroundStyle(DSColor.accent) }
        }
        .font(DSFont.caption)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Progress score

private struct PaceCard: View {
    let model: ProgressModel

    var body: some View {
        ChartCard(title: "progress.pace.title", identifier: "progress-pace") { EmptyView() } content: {
            switch model.pace {
            case .unknown:
                Text("progress.pace.unknown").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            case .faster, .onTrack, .slower:
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                        Text(headline).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    }
                    if let observed = model.observedPercentText, let expected = model.expectedPercentText {
                        Text("progress.pace.detail \(observed) \(expected)").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    Text("progress.pace.explain").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
                }
            }
        }
    }

    private var headline: LocalizedStringKey {
        switch model.pace {
        case .faster: "progress.pace.faster"
        case .slower: "progress.pace.slower"
        default: "progress.pace.onTrack"
        }
    }

    private var icon: String {
        switch model.pace {
        case .faster: "arrow.up.right.circle.fill"
        case .slower: "arrow.down.right.circle.fill"
        default: "equal.circle.fill"
        }
    }

    private var color: Color { model.pace == .faster ? DSColor.success : (model.pace == .slower ? DSColor.warning : DSColor.accent) }
}

// MARK: - Score over time

private struct ScoreSeriesCard: View {
    let model: ProgressModel
    @State private var selection: Date?

    var body: some View {
        ChartCard(title: "progress.score.title", identifier: "progress-score") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("progress.score.scope", selection: Binding(get: { model.scoreScope }, set: { model.scoreScope = $0 })) {
                    Text("progress.score.scope.overall").tag(ProgressModel.ScoreScope.overall)
                    Text("progress.score.scope.exercise").tag(ProgressModel.ScoreScope.exercise)
                    Text("progress.score.scope.muscle").tag(ProgressModel.ScoreScope.muscle)
                }
                .pickerStyle(.segmented)
                if model.scoreScope == .muscle {
                    Picker("progress.score.muscle", selection: Binding(get: { model.muscle ?? "" }, set: { model.muscle = $0 })) {
                        ForEach(model.muscles, id: \.self) { key in
                            Text(verbatim: Muscle(rawValue: key)?.localizedName(locale: model.locale) ?? key).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if let point = selectedPoint ?? model.scorePoints.last {
                    Readout(value: "\(Int(point.score.rounded()))", caption: model.dateText(point.date))
                }
            }
        } content: {
            if model.scorePoints.count >= 2 {
                Chart {
                    ForEach(model.scorePoints, id: \.date) { point in
                        LineMark(x: .value("date", point.date), y: .value("score", point.score)).foregroundStyle(DSColor.accent)
                            .interpolationMethod(.monotone)
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("date", point.date)).foregroundStyle(DSColor.textTertiary)
                        PointMark(x: .value("date", point.date), y: .value("score", point.score)).foregroundStyle(DSColor.accent)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXSelection(value: $selection)
                .frame(height: 180)
                .accessibilityLabel(Text("progress.score.title"))
                .accessibilityValue(Text(verbatim: model.scorePoints.last.map { "\(Int($0.score.rounded()))" } ?? ""))
            } else {
                EmptyChartText(key: "progress.score.empty")
            }
        }
    }

    private var selectedPoint: ScorePoint? {
        selection.flatMap { ProgressModel.nearest(model.scorePoints, to: $0, at: \.date) }
    }
}

// MARK: - Volume

private struct VolumeCard: View {
    let model: ProgressModel
    @State private var stacked = false
    @State private var selection: Date?

    private static let shades: [VolumeBucket: Double] = [.chest: 1, .back: 0.8, .shoulders: 0.62, .arms: 0.46, .legs: 0.32, .core: 0.2]

    var body: some View {
        ChartCard(title: "progress.volume.title", identifier: "progress-volume") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("progress.volume.mode", selection: $stacked) {
                    Text("progress.volume.mode.total").tag(false)
                    Text("progress.volume.mode.muscle").tag(true)
                }
                .pickerStyle(.segmented)
                if let week = selectedWeek ?? model.volume.last {
                    Readout(value: "\(week.totalSets)", caption: model.dateText(week.date), note: "progress.volume.caption")
                }
            }
        } content: {
            if model.volume.contains(where: { $0.totalSets > 0 }) {
                chart
                if stacked { legend }
            } else {
                EmptyChartText(key: "progress.volume.empty")
            }
        }
    }

    private var selectedWeek: WeekVolume? { selection.flatMap { ProgressModel.nearest(model.volume, to: $0, at: \.date) } }

    private var chart: some View {
        Chart {
            if stacked {
                ForEach(model.volume) { week in
                    ForEach(VolumeBucket.allCases) { bucket in
                        BarMark(x: .value("week", week.date, unit: .weekOfYear), y: .value("sets", week.buckets[bucket] ?? 0))
                            .foregroundStyle(DSColor.accent.opacity(Self.shades[bucket] ?? 0.5))
                    }
                }
            } else {
                ForEach(model.volume) { week in
                    BarMark(x: .value("week", week.date, unit: .weekOfYear), y: .value("sets", week.totalSets)).foregroundStyle(DSColor.accent)
                }
            }
            if let week = selectedWeek { RuleMark(x: .value("week", week.date, unit: .weekOfYear)).foregroundStyle(DSColor.textTertiary) }
        }
        .chartXSelection(value: $selection)
        .frame(height: 190)
        .accessibilityLabel(Text("progress.volume.title"))
        .accessibilityValue(Text(verbatim: model.volume.last.map { "\($0.totalSets)" } ?? ""))
    }

    private var legend: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(VolumeBucket.allCases) { bucket in
                HStack(spacing: Spacing.xxs) {
                    Circle().fill(DSColor.accent.opacity(Self.shades[bucket] ?? 0.5)).frame(width: 8, height: 8)
                    Text(LocalizedStringKey.dynamic("progress.bucket.\(bucket.rawValue)")).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Calendar

private struct FrequencyCard: View {
    let model: ProgressModel

    var body: some View {
        ChartCard(title: "progress.frequency.title", identifier: "progress-frequency") {
            Text("progress.frequency.summary \(workoutCount) \(activeDays)").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        } content: {
            if workoutCount > 0 {
                Chart(model.calendarCells) { cell in
                    RectangleMark(x: .value("week", cell.week), y: .value("day", 6 - cell.weekday), width: .fixed(9), height: .fixed(9))
                        .foregroundStyle(color(cell.workouts))
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...6)
                .frame(height: 100)
                .accessibilityLabel(Text("progress.frequency.title"))
                .accessibilityValue(Text("progress.frequency.summary \(workoutCount) \(activeDays)"))
            } else {
                EmptyChartText(key: "progress.frequency.empty")
            }
        }
    }

    private var workoutCount: Int { model.calendarCells.reduce(0) { $0 + $1.workouts } }
    private var activeDays: Int { model.calendarCells.filter { $0.workouts > 0 }.count }

    private func color(_ count: Int) -> Color {
        switch count {
        case 0: DSColor.surfaceOverlay
        case 1: DSColor.accent.opacity(0.6)
        default: DSColor.accent
        }
    }
}

// MARK: - Bodyweight and relative strength

private struct BodyweightCard: View {
    let model: ProgressModel
    @State private var selection: Date?

    var body: some View {
        ChartCard(title: "progress.body.title", identifier: "progress-body") {
            if let point = selectedWeight ?? model.bodyweightPoints.last {
                Readout(value: model.weightText(point.weightKg), caption: model.dateText(point.date))
            }
        } content: {
            if model.bodyweightPoints.count >= 2 {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Chart {
                        ForEach(model.bodyweightPoints) { point in
                            LineMark(x: .value("date", point.date), y: .value("weight", model.displayWeight(point.weightKg))).foregroundStyle(DSColor.accent)
                        }
                        if let point = selectedWeight {
                            RuleMark(x: .value("date", point.date)).foregroundStyle(DSColor.textTertiary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel(model.unit.symbol, position: .topLeading)
                    .chartXSelection(value: $selection)
                    .frame(height: 140)
                    relative
                }
            } else {
                EmptyChartText(key: "progress.body.empty")
            }
        }
    }

    private var selectedWeight: BodyweightPoint? { selection.flatMap { ProgressModel.nearest(model.bodyweightPoints, to: $0, at: \.date) } }

    @ViewBuilder private var relative: some View {
        if model.relativePoints.count >= 2 {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("progress.body.relative \(model.exerciseName)").font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                if let last = model.relativePoints.last {
                    Text("progress.body.relative.value \(last.ratio.formatted(.number.precision(.fractionLength(2)).locale(model.locale)))")
                        .font(DSFont.numericSmall).foregroundStyle(DSColor.textSecondary)
                }
                Chart(model.relativePoints) { point in
                    LineMark(x: .value("date", point.date), y: .value("ratio", point.ratio)).foregroundStyle(DSColor.success)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
            }
        }
    }
}
