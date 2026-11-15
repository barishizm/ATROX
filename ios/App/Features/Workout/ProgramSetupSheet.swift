import DataKit
import DesignSystem
import SwiftUI

/// Called when a create flow is finished: the tab that started it goes back to its first screen, so nobody has to
/// press back several times.
private struct FinishCreationKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    var finishCreation: (@MainActor @Sendable () -> Void)? {
        get { self[FinishCreationKey.self] }
        set { self[FinishCreationKey.self] = newValue }
    }
}

/// What the setup sheet creates.
enum ProgramSetupSource {
    case scratch
    case template(TemplateListModel, ProgramTemplate, useAlternatives: Bool)
}

/// The questions asked before programs are created (which days will you train, what is each day called), then a
/// "done" page that sends the user back to the Workout tab.
struct ProgramSetupSheet: View {
    let source: ProgramSetupSource
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.finishCreation) private var finish
    @Environment(AppContainer.self) private var container

    private enum Phase: Equatable {
        case questions
        case working
        case done([String])
    }

    @State private var phase: Phase = .questions
    @State private var selected: Set<Int>
    @State private var names: [Int: String] = [:]
    @State private var failed = false

    init(source: ProgramSetupSource) {
        self.source = source
        switch source {
        case .scratch: _selected = State(initialValue: [1, 3, 5])
        case .template(_, let template, _): _selected = State(initialValue: Self.defaultDays(template.daysPerWeek))
        }
    }

    private var languageCode: String { locale.language.languageCode?.identifier == "tr" ? "tr" : "en" }

    /// Weekday numbers follow `Calendar` (0 = Sunday … 6 = Saturday); the picker shows Monday first.
    private static let order = [1, 2, 3, 4, 5, 6, 0]

    private static func defaultDays(_ count: Int) -> Set<Int> {
        switch count {
        case ...1: [1]
        case 2: [1, 4]
        case 3: [1, 3, 5]
        case 4: [1, 2, 4, 5]
        case 5: [1, 2, 3, 4, 5]
        case 6: [1, 2, 3, 4, 5, 6]
        default: Set(0...6)
        }
    }

    private var symbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortWeekdaySymbols
    }

    /// "Friday workout": named after the weekday, because the n-th chosen day is not the n-th day of the week.
    private func defaultName(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let weekday = calendar.weekdaySymbols[day]
        return languageCode == "tr" ? "\(weekday) antrenmanı" : "\(weekday) workout"
    }

    private var sortedDays: [Int] { Self.order.filter(selected.contains) }

    /// How many days the user has to pick: exactly the template's days, or any number for a program from scratch.
    private var requiredCount: Int? {
        if case .template(_, let template, _) = source { return template.daysPerWeek }
        return nil
    }

    private var isReady: Bool {
        if let requiredCount { return selected.count == requiredCount }
        return !selected.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .done(let created) = phase {
                    done(created)
                } else {
                    questions
                }
            }
            .background(DSColor.background)
            .navigationTitle("workout.setup.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = phase {
                        EmptyView()
                    } else {
                        Button("routine.action.cancel") { dismiss() }.accessibilityIdentifier("setup-cancel")
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase != .questions)
        .alert("routine.error.save", isPresented: $failed) {
            Button("routine.action.ok", role: .cancel) {}
        }
        .accessibilityIdentifier("program-setup-root")
    }

    // MARK: - Questions

    private var questions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("workout.setup.days.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    if let requiredCount {
                        Text("workout.setup.days.hint.exact \(requiredCount)")
                            .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    } else {
                        Text("workout.setup.days.hint.any").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    weekdayPicker
                }
                switch source {
                case .template(let model, let template, _): weekPlan(model.personalized(template))
                case .scratch: dayNames
                }
                PrimaryButton("workout.setup.create", isLoading: phase == .working) { Task { await create() } }
                    .disabled(!isReady)
                    .accessibilityIdentifier("setup-create")
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Self.order, id: \.self) { day in
                let on = selected.contains(day)
                Button {
                    Haptics.play(.light)
                    if on { selected.remove(day) } else { selected.insert(day) }
                } label: {
                    Text(verbatim: symbols[day])
                        .font(DSFont.callout.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? DSColor.onAccent : DSColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            on ? DSColor.accentFill : DSColor.surface,
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("setup-day-\(day)")
            }
        }
    }

    /// Template: which training day lands on which weekday.
    private func weekPlan(_ personalized: PersonalizedTemplate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("workout.setup.plan.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(personalized.days.enumerated()), id: \.offset) { index, day in
                        HStack {
                            Text(verbatim: day.name.resolve(languageCode: languageCode))
                                .font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                            Spacer(minLength: Spacing.sm)
                            Text(verbatim: index < sortedDays.count ? symbols[sortedDays[index]] : "–")
                                .font(DSFont.body.weight(.semibold)).foregroundStyle(DSColor.accent)
                        }
                    }
                }
            }
        }
    }

    /// Scratch: a name for the program of each chosen weekday.
    @ViewBuilder
    private var dayNames: some View {
        if !sortedDays.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("workout.setup.names.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(sortedDays.enumerated()), id: \.element) { _, day in
                            HStack(spacing: Spacing.md) {
                                Text(verbatim: symbols[day])
                                    .font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.accent)
                                    .frame(width: 44, alignment: .leading)
                                TextField(
                                    defaultName(day),
                                    text: Binding(get: { names[day] ?? "" }, set: { names[day] = $0 })
                                )
                                .textInputAutocapitalization(.words)
                                .accessibilityIdentifier("setup-name-\(day)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Create

    private func create() async {
        guard isReady, phase == .questions else { return }
        phase = .working
        let labels = sortedDays.map { symbols[$0] }
        // `Calendar` weekdays run 1 (Sunday) … 7 (Saturday); the picker's numbers run 0 … 6.
        let weekdays = sortedDays.map { $0 + 1 }
        var created: [String]?
        switch source {
        case .template(let model, let template, let useAlternatives):
            created = await model.use(
                template, languageCode: languageCode, useAlternatives: useAlternatives, weekdayLabels: labels,
                weekdays: weekdays)
        case .scratch:
            var made: [String] = []
            let model = await container.makeRoutineListModel()
            for (index, day) in sortedDays.enumerated() {
                let typed = (names[day] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let base = typed.isEmpty ? (languageCode == "tr" ? "Antrenman" : "Workout") : typed
                let name = typed.isEmpty ? defaultName(day) : "\(typed) · \(labels[index])"
                if let id = await model?.create(name: name, firstDayName: base) {
                    made.append(name)
                    if let day = model?.routines.first(where: { $0.id == id })?.days.first {
                        model?.plan.assign(dayId: day.id, toWeekday: weekdays[index])
                    }
                }
            }
            created = made.isEmpty ? nil : made
        }
        if let created {
            phase = .done(created)
        } else {
            phase = .questions
            failed = true
        }
    }

    // MARK: - Done

    private func done(_ created: [String]) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(DSColor.accent.opacity(0.13)).frame(width: 138, height: 138)
                Circle().fill(DSColor.accentFill).frame(width: 92, height: 92)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold)).foregroundStyle(DSColor.onAccent)
            }
            .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text("workout.setup.done.title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                Text("workout.setup.done.message")
                    .font(DSFont.callout).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
            }
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(created, id: \.self) { name in
                        Label { Text(verbatim: name).foregroundStyle(DSColor.textPrimary) } icon: {
                            Image(systemName: "dumbbell.fill").foregroundStyle(DSColor.accent)
                        }
                        .font(DSFont.body)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            PrimaryButton("workout.setup.done.button") {
                finish?()
                dismiss()
            }
            .accessibilityIdentifier("setup-done")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden()
    }
}
