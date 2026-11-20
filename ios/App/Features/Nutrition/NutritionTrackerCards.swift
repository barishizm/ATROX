import DataKit
import DesignSystem
import SwiftUI

/// A section title with an optional trailing action, like "Nutrition … More".
struct DiarySectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title).font(DSFont.title).foregroundStyle(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
    }
}

/// Today's water: tap a glass to fill it, tap the last full one to take it back.
struct WaterCard: View {
    let model: NutritionModel
    @Environment(\.locale) private var locale

    private var glasses: Int { max(Int((model.waterGoalMl / NutritionModel.glassMl).rounded(.up)), 1) }
    private var filled: Int { Int((model.waterMl / NutritionModel.glassMl).rounded(.down)) }

    var body: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                Text("nutrition.water.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text("nutrition.water.goal \(liters(model.waterGoalMl))").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                Text(verbatim: liters(model.waterMl)).font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 7), spacing: Spacing.sm) {
                    ForEach(0..<max(glasses, filled + 1), id: \.self) { index in
                        Button { Task { index < filled ? await model.removeWater() : await model.addWater() } } label: {
                            WaterGlass(isFull: index < filled)
                                .frame(width: 26, height: 32)
                                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        }
                        .accessibilityLabel(Text(index < filled ? "nutrition.water.remove" : "nutrition.water.add"))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("nutrition-water")
    }

    private func liters(_ ml: Double) -> String {
        (ml / 1000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " L"
    }
}

/// A drinking glass, wider at the top; filled with water when `isFull`.
private struct WaterGlass: View {
    let isFull: Bool

    private struct Tumbler: Shape {
        /// Fraction of the height the water reaches; 1 draws the whole glass.
        var level: CGFloat = 1

        func path(in rect: CGRect) -> Path {
            let inset = rect.width * 0.14
            let top = rect.maxY - rect.height * level
            // Width of the glass at height y: linear from full at the top to narrower at the bottom.
            func edge(_ y: CGFloat) -> CGFloat { inset * (y - rect.minY) / rect.height }
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + edge(top), y: top))
            path.addLine(to: CGPoint(x: rect.maxX - edge(top), y: top))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    var body: some View {
        ZStack {
            if isFull { Tumbler(level: 0.78).fill(DSColor.accent.opacity(0.85)) }
            Tumbler().stroke(isFull ? DSColor.accent : DSColor.textTertiary, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .padding(2)
        .accessibilityHidden(true)
    }
}

/// Weight with ± 0.1 steps, the goal, and the way into the history.
struct WeightCard: View {
    let model: NutritionModel
    let onGoal: () -> Void
    let onEntry: () -> Void
    let onProgress: () -> Void
    @Environment(\.locale) private var locale

    private var unit: WeightUnit { model.profile?.weightUnit ?? .kilograms }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: Spacing.sm) {
                    Text("nutrition.weight.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Button(action: onGoal) {
                        Group {
                            if let goal = model.goalWeightKg { Text("nutrition.weight.goal \(text(goal))") } else { Text("nutrition.weight.goal.set") }
                        }
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    .accessibilityIdentifier("nutrition-weight-goal")
                    if let kg = model.weightKg {
                        HStack(spacing: Spacing.lg) {
                            stepper("minus.circle", "nutrition.weight.less", -1)
                            Text(verbatim: text(kg)).font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                            stepper("plus.circle", "nutrition.weight.more", 1)
                        }
                    } else {
                        PrimaryButton("nutrition.weight.add", action: onEntry).accessibilityIdentifier("nutrition-weight-add")
                    }
                }
                .padding(Spacing.md)
                Divider().overlay(DSColor.separator)
                Button(action: onProgress) {
                    Text("nutrition.weight.progress").font(DSFont.headline).foregroundStyle(DSColor.accent)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.button)
                }
                .accessibilityIdentifier("nutrition-weight-progress")
            }
        }
        .accessibilityIdentifier("nutrition-weight")
    }

    private func text(_ kg: Double) -> String {
        unit.value(fromKilograms: kg).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " " + unit.symbol
    }

    private func stepper(_ symbol: String, _ label: LocalizedStringKey, _ direction: Double) -> some View {
        Button { Task { await model.adjustWeight(by: direction * (unit.kilograms(from: 0.1))) } } label: {
            Image(systemName: symbol).font(.title).frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
        }
        .foregroundStyle(DSColor.textPrimary)
        .accessibilityLabel(Text(label))
    }
}

/// Fasting: start a plan, watch the timer, end it.
struct FastingCard: View {
    let model: NutritionModel
    let onStart: () -> Void

    var body: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                if let active = model.activeFast {
                    activeContent(active)
                } else {
                    Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(DSColor.highlight).accessibilityHidden(true)
                    Text("nutrition.fasting.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text("nutrition.fasting.subtitle").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    if let last = model.lastFinishedFast, let end = last.input.endedAt {
                        Text("nutrition.fasting.last \(Self.duration(end.timeIntervalSince(last.input.at)))")
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                    PrimaryButton("nutrition.fasting.start", action: onStart).accessibilityIdentifier("nutrition-fasting-start")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("nutrition-fasting")
    }

    private func activeContent(_ fast: DiaryLogSnapshot) -> some View {
        let planned = fast.input.quantity * 3600
        return VStack(spacing: Spacing.sm) {
            Text(verbatim: fast.input.label).font(DSFont.overline).foregroundStyle(DSColor.textSecondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(context.date.timeIntervalSince(fast.input.at), 0)
                VStack(spacing: Spacing.xs) {
                    Text(verbatim: Self.clock(elapsed)).font(DSFont.display.monospacedDigit()).foregroundStyle(DSColor.textPrimary)
                    ProgressView(value: min(elapsed / planned, 1)).tint(DSColor.highlight)
                    Text(elapsed >= planned ? "nutrition.fasting.done" : "nutrition.fasting.remaining \(Self.duration(planned - elapsed))")
                        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
            }
            SecondaryButton("nutrition.fasting.end") { Task { await model.endFast() } }.accessibilityIdentifier("nutrition-fasting-end")
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// Steps and the activities logged for the day.
struct ActivitiesCard: View {
    let model: NutritionModel
    let onSteps: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Card {
                VStack(spacing: Spacing.sm) {
                    Text("nutrition.steps.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    if model.stepsConnected || model.manualSteps > 0 {
                        Text(verbatim: Int(model.totalSteps).formatted()).font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                        Text(model.stepsConnected ? "nutrition.steps.fromhealth" : "nutrition.steps.manual")
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    } else {
                        Text("nutrition.steps.auto").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                        if model.health != nil {
                            PrimaryButton("nutrition.steps.connect") { Task { await model.connectSteps() } }
                                .accessibilityIdentifier("nutrition-steps-connect")
                        }
                    }
                    if !model.stepsConnected {
                        Button(action: onSteps) { Text("nutrition.steps.addmanual").font(DSFont.headline).foregroundStyle(DSColor.accent) }
                            .frame(minHeight: HitTarget.minimum).accessibilityIdentifier("nutrition-steps-manual")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(model.activities) { log in
                Card(padding: Spacing.sm) {
                    HStack {
                        Image(systemName: "figure.run").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(verbatim: log.input.label).font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                            Text("nutrition.activity.minutes \(Int(log.input.quantity))").font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer()
                        Text(verbatim: "\(Int(log.input.amount)) kcal").font(DSFont.numericSmall).foregroundStyle(DSColor.textPrimary)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { Task { await model.deleteLog(id: log.id) } } label: {
                        Label("nutrition.entry.delete", systemImage: "trash")
                    }
                }
            }
            Button(action: onAdd) {
                Label("nutrition.activity.add", systemImage: "plus.circle").font(DSFont.headline)
            }
            .frame(minHeight: HitTarget.minimum).accessibilityIdentifier("nutrition-activity-add")
        }
        .accessibilityIdentifier("nutrition-activities")
    }
}

/// How the day went: a mood and a few words.
struct NotesCard: View {
    let model: NutritionModel
    let onEdit: () -> Void

    var body: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                if let note = model.note {
                    HStack(spacing: Spacing.sm) {
                        Text(verbatim: Self.emoji(note.input.label)).font(.largeTitle)
                        Text(verbatim: note.input.text).font(DSFont.callout).foregroundStyle(DSColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: onEdit) { Text("nutrition.note.edit").font(DSFont.headline).foregroundStyle(DSColor.accent) }
                        .frame(minHeight: HitTarget.minimum)
                } else {
                    Text("nutrition.note.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text("nutrition.note.subtitle").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    PrimaryButton("nutrition.note.add", action: onEdit).accessibilityIdentifier("nutrition-note-add")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("nutrition-notes")
    }

    static func emoji(_ mood: String) -> String {
        switch mood {
        case "great": "😄"
        case "good": "🙂"
        case "okay": "😐"
        case "bad": "🙁"
        default: "😣"
        }
    }
}
