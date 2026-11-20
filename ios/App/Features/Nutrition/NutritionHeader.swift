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
    let streak: Int
    let onCalendar: () -> Void
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack(spacing: Spacing.sm) {
            title.font(DSFont.display).foregroundStyle(DSColor.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
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
            .background(DSColor.surfaceRaised, in: Capsule())
        }
    }
}

/// Diary | Recipes switch under the header.
struct NutritionTabPicker: View {
    @Binding var selection: NutritionTab

    var body: some View {
        Picker("nutrition.tab.picker", selection: $selection) {
            ForEach(NutritionTab.allCases) { Text($0.titleKey).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("nutrition-tabs")
    }
}

/// Date picker sheet, capped at today.
struct NutritionCalendarSheet: View {
    @State var selection: Date
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

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
