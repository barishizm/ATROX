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
            .glassEffect(Glass.regular.tint(dsGlassDim), in: Capsule())
        }
    }
}

/// Diary | Recipes switch under the header, drawn as a glass capsule with a tinted glass thumb.
struct NutritionTabPicker: View {
    @Binding var selection: NutritionTab

    var body: some View {
        GlassEffectContainer(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                ForEach(NutritionTab.allCases) { tab in
                    Button { withAnimation(.snappy) { selection = tab } } label: {
                        Text(tab.titleKey).font(DSFont.headline)
                            .foregroundStyle(selection == tab ? DSColor.onAccent : DSColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selection == tab ? Glass.regular.tint(DSColor.accentFill).interactive() : Glass.regular.tint(dsGlassDim).interactive(),
                        in: Capsule()
                    )
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier("nutrition-tab-\(tab.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition-tabs")
    }
}

/// Soft brand-colour glows behind the page, so the glass has something to bend.
struct NutritionBackdrop: View {
    var body: some View {
        ZStack {
            DSColor.background
            RadialGradient(colors: [DSColor.accentFill.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
            RadialGradient(colors: [DSColor.highlightFill.opacity(0.22), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
        }
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
