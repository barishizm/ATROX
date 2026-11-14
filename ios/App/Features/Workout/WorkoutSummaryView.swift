import DataKit
import DesignSystem
import SwiftUI

/// Shown right after a workout is finished (P041): duration, volume, sets, muscles, records, comparison with the
/// last similar workout, and an optional name, note and feeling. The coach comment and the score change are
/// placeholder until the score change lands.
struct WorkoutSummaryView: View {
    @Bindable var model: WorkoutSummaryModel
    let done: () -> Void
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    stats
                    if !model.recordRows.isEmpty { recordsSection }
                    musclesSection
                    comparisonSection
                    feelingSection
                    notesSection
                    placeholders
                }
                .padding(Spacing.md)
            }
            .background(DSColor.background)
            .navigationTitle("summary.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("summary.done") {
                        isSaving = true
                        Task {
                            if await model.save() { done() }
                            isSaving = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                    .accessibilityIdentifier("summary-done")
                }
            }
        }
        .task { await model.loadComment() }
        .interactiveDismissDisabled()
        .alert("workout.error.title", isPresented: Binding(get: { model.errorKey != nil }, set: { if !$0 { model.clearError() } })) {
            Button("workout.ok", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(model.errorKey ?? "workout.error.generic"))
        }
        .accessibilityIdentifier("workout-summary")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("summary.headline", systemImage: "checkmark.seal.fill")
                .font(DSFont.title).foregroundStyle(DSColor.accent)
            TextField("summary.name.placeholder", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("summary-name")
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            StatTile("summary.duration", value: model.durationText)
            StatTile("summary.volume", value: model.volumeText, unit: model.unit.symbol)
            StatTile("summary.sets", value: "\(model.summary.setCount)")
            StatTile("summary.exercises", value: "\(model.summary.exerciseCount)")
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("summary.records")
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(model.recordRows) { row in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: row.exercise).font(DSFont.callout)
                                Text(ActiveWorkoutView.recordName(row.kind))
                                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            Text(verbatim: row.valueText).font(DSFont.numericSmall)
                            RecordShareButton(exercise: row.exercise, kind: row.kind, value: row.valueText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityIdentifier("summary-records")
    }

    private var musclesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("summary.muscles")
            Card {
                if model.muscleIntensities.isEmpty {
                    Text("summary.muscles.empty").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                } else {
                    MuscleMapView(intensities: model.muscleIntensities)
                        .frame(height: 260)
                }
            }
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("summary.comparison")
            Card {
                if let change = model.volumeChange, let comparison = model.summary.comparison {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("summary.comparison.since \(comparison.previousDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        Label(change.text, systemImage: icon(change.direction))
                            .font(DSFont.numericMedium).foregroundStyle(color(change.direction))
                        Text("summary.comparison.sets \(comparison.setDelta)")
                            .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                } else {
                    Text("summary.comparison.first").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("summary-comparison")
    }

    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("summary.feeling")
            HStack(spacing: Spacing.sm) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        model.rating = model.rating == value ? nil : value
                    } label: {
                        Image(systemName: (model.rating ?? 0) >= value ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle((model.rating ?? 0) >= value ? DSColor.accent : DSColor.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel("summary.feeling.value \(value)")
                    .accessibilityIdentifier("summary-feeling-\(value)")
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("summary.notes")
            TextField("summary.notes.placeholder", text: $model.notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("summary-notes")
        }
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            coachComment
            Card {
                Label("summary.score.placeholder", systemImage: "chart.line.uptrend.xyaxis")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    @ViewBuilder private var coachComment: some View {
        switch model.comment {
        case .hidden:
            EmptyView()
        case .loading:
            Card {
                Text(verbatim: "Placeholder comment text that stands in while the coach writes, spanning two lines.")
                    .font(DSFont.callout).redacted(reason: .placeholder)
            }
            .accessibilityIdentifier("summary-coach-loading")
        case .ready(let comment):
            Card {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("summary.coach.title", systemImage: "bubble.left.and.text.bubble.right")
                        .font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
                    Text(verbatim: comment.text).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                    if comment.onDevice {
                        Label("summary.coach.onDevice", systemImage: "iphone")
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summary-coach-comment")
        }
    }

    private func icon(_ direction: ChangeDirection) -> String {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func color(_ direction: ChangeDirection) -> Color {
        switch direction {
        case .up: DSColor.success
        case .down: DSColor.warning
        case .flat: DSColor.textSecondary
        }
    }
}
