import DesignSystem
import SwiftUI

/// Shown to free users who tap the camera: what photo logging does, then the paywall.
struct FoodProPromoView: View {
    let onClose: () -> Void
    @State private var showsPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                    .frame(width: 44, height: 44).glassEffect(Glass.regular.interactive(), in: Circle())
            }
            .accessibilityLabel(Text("nutrition.camera.close"))
            .accessibilityIdentifier("food-promo-close")
            Spacer(minLength: 0)
            example
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("nutrition.promo.title").font(DSFont.display).foregroundStyle(DSColor.textPrimary).minimumScaleFactor(0.7)
                Text("nutrition.promo.message").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 0)
            PrimaryButton("nutrition.promo.cta", systemImage: "bolt.fill") { showsPaywall = true }
                .accessibilityIdentifier("food-promo-unlock")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSColor.background.ignoresSafeArea())
        .sheet(isPresented: $showsPaywall) { NavigationStack { PaywallView(feature: .foodAnalysisUnlimited) } }
        .accessibilityIdentifier("food-promo")
    }

    /// A stand-in for the result screen: a plate, what was recognised, and the macros.
    private var example: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient(colors: [DSColor.accentFill.opacity(0.35), DSColor.highlightFill.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "camera.viewfinder").font(.system(size: 64)).foregroundStyle(DSColor.textPrimary).accessibilityHidden(true)
                }
                .frame(height: 150)
                Text("nutrition.promo.example").font(DSFont.headline).foregroundStyle(DSColor.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(verbatim: "540 kcal").font(DSFont.numericSmall)
                    Spacer()
                    MacroLine(protein: 42, carbs: 55, fat: 14).font(DSFont.numericSmall)
                }
                .foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }
}
