import DesignSystem
import SwiftUI

/// The two halves of the nutrition screen.
enum NutritionTab: String, CaseIterable, Identifiable {
    case diary, recipes
    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .diary: "nutrition.tab.diary"
        case .recipes: "nutrition.tab.recipes"
        }
    }
}

/// Day title on the left; streak, calendar and options on the right.
struct NutritionHeader<Options: View>: View {
    let title: Text
    /// Used when `title` does not fit on one line.
    let shortTitle: Text
    let streak: Int
    let onCalendar: () -> Void
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                title.lineLimit(1)
                shortTitle.lineLimit(1)
                shortTitle.lineLimit(1).minimumScaleFactor(0.5)
            }
            .font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            HStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? DSColor.highlight : DSColor.textTertiary)
                    Text(verbatim: "\(streak)").font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("nutrition.streak.a11y \(streak)"))
                .accessibilityIdentifier("nutrition-streak")
                Button(action: onCalendar) { Image(systemName: "calendar").font(.title3.weight(.semibold)) }
                    .accessibilityLabel(Text("nutrition.calendar.open"))
                    .accessibilityIdentifier("nutrition-calendar")
                options()
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: HitTarget.minimum)
            .glassEffect(Glass.regular.tint(dsGlassDim), in: Capsule())
        }
    }
}

/// Diary | Recipes switch under the header, drawn as a glass capsule with a tinted glass thumb.
struct NutritionTabPicker: View {
    @Binding var selection: NutritionTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NutritionTab.allCases) { tab in
                Button { withAnimation(.snappy) { selection = tab } } label: {
                    Text(tab.titleKey).font(DSFont.headline)
                        .foregroundStyle(selection == tab ? DSColor.onAccent : DSColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .background {
                            if selection == tab {
                                Capsule().fill(DSColor.accentFill).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("nutrition-tab-\(tab.rawValue)")
            }
        }
        .padding(Spacing.xxs)
        .glassEffect(Glass.regular.tint(dsGlassDim), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-tabs")
    }
}

/// Pure black page background.
struct NutritionBackdrop: View {
    var body: some View {
        Color.black
    }
}

/// Date picker sheet, capped at today.
struct NutritionCalendarSheet: View {
    /// One-time seed: the picker owns the value after the sheet opens.
    @State private var selection: Date
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    init(selection: Date, onSelect: @escaping (Date) -> Void) {
        _selection = State(initialValue: selection)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            DatePicker("nutrition.calendar.open", selection: $selection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(Spacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(DSColor.background.ignoresSafeArea())
                .navigationTitle("nutrition.calendar.open")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("nutrition.calendar.done") { onSelect(selection); dismiss() }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                }
        }
        .presentationDetents([.medium])
    }
}
