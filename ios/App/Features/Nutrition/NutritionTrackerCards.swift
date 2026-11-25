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

/// Today's water: a row per cup size, smallest to largest, each with a + that logs it.
struct WaterCard: View {
    let model: NutritionModel
    /// Lets a page match the height of the summary card.
    var minHeight: CGFloat = 0
    @Environment(\.locale) private var locale
    /// The cup whose + is showing its green confirmation.
    @State private var confirmed: Double?
    @State private var tick = 0

    private static let cups: [(ml: Double, symbol: String, name: LocalizedStringKey, label: String)] = [
        (125, "cup.and.saucer.fill", "nutrition.water.cup.tea", "125 ml"),
        (250, "mug.fill", "nutrition.water.cup.glass", "250 ml"),
        (500, "waterbottle.fill", "nutrition.water.cup.large", "500 ml"),
        (1000, "flask.fill", "nutrition.water.cup.jug", "1 L")
    ]

    /// 1 = the goal, where the water reaches the top of the card.
    private var progress: Double { model.waterMl / max(model.waterGoalMl, 1) }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                tank
                ForEach(Self.cups, id: \.ml) { cup in
                    Divider().overlay(DSColor.separator)
                    row(cup)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .sensoryFeedback(.success, trigger: tick)
        .accessibilityIdentifier("nutrition-water")
    }

    /// The part above the cup rows: water rises in it as the day's total grows, and reaches the top of the card at the goal.
    private var tank: some View {
        let level = min(max(progress, 0), 1)
        let topShape = UnevenRoundedRectangle(topLeadingRadius: Radius.lg, topTrailingRadius: Radius.lg, style: .continuous)
        return ZStack {
            TimelineView(.animation) { context in
                WaterSurface(level: level, phase: context.date.timeIntervalSinceReferenceDate * 2.2)
                    .fill(LinearGradient(colors: [DSColor.accentFill, DSColor.accentFill.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .animation(.easeInOut(duration: 1.1), value: level)
            }
            .clipShape(topShape)
            VStack(spacing: Spacing.sm) {
                Text("nutrition.water.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text(verbatim: liters(model.waterMl)).font(DSFont.display).foregroundStyle(DSColor.textPrimary)
                Text("nutrition.water.goal \(liters(model.waterGoalMl))").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.waterMl > 0 {
                Button { Task { await model.removeWater() } } label: {
                    Image(systemName: "arrow.uturn.backward").font(.callout.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                }
                .accessibilityLabel(Text("nutrition.water.undo"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 150)
    }

    private func row(_ cup: (ml: Double, symbol: String, name: LocalizedStringKey, label: String)) -> some View {
        let done = confirmed == cup.ml
        return HStack(spacing: Spacing.sm) {
            Image(systemName: cup.symbol).font(.title3).foregroundStyle(DSColor.accent)
                .frame(width: 44, height: 44).glassEffect(Glass.regular, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(cup.name).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text(verbatim: cup.label).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button { add(cup.ml) } label: {
                Image(systemName: done ? "checkmark" : "plus").font(.title3.weight(.bold)).foregroundStyle(DSColor.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .glassEffect(Glass.regular.tint(done ? DSColor.success : DSColor.accentFill).interactive(), in: Circle())
                    .frame(width: HitTarget.minimum, height: HitTarget.minimum)
            }
            .accessibilityLabel(Text("nutrition.add.more"))
        }
        .padding(Spacing.sm)
    }

    private func add(_ ml: Double) {
        Task { await model.addWater(ml: ml) }
        tick += 1
        withAnimation(.snappy) { confirmed = ml }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { if confirmed == ml { confirmed = nil } }
        }
    }

    private func liters(_ ml: Double) -> String {
        (ml / 1000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " L"
    }
}

/// The water: a wave whose surface sits at `level` (0 empty, 1 full) of the height.
private struct WaterSurface: Shape {
    var level: CGFloat
    var phase: Double

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0.001 else { return path }
        let top = rect.height * (1 - level)
        let amplitude = 5 * sin(Double.pi * Double(min(level, 1)))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 4) {
            let y = top + amplitude * sin(Double(x / max(rect.width, 1)) * 2 * .pi * 1.5 + phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Fasting: start a plan, watch the timer, end it.
struct FastingCard: View {
    let model: NutritionModel
    /// Lets a page match the height of the summary card.
    var minHeight: CGFloat = 0
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
                    PrimaryButton("nutrition.fasting.start") { onStart() }.accessibilityIdentifier("nutrition-fasting-start")
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(minHeight - 2 * Spacing.md, 0))
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

/// How the day went: a mood and a few words.
struct NotesCard: View {
    let model: NutritionModel
    /// Lets a page match the height of the summary card.
    var minHeight: CGFloat = 0
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
                    PrimaryButton("nutrition.note.add") { onEdit() }.accessibilityIdentifier("nutrition-note-add")
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(minHeight - 2 * Spacing.md, 0))
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
