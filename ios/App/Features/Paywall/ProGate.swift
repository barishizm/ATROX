import DesignSystem
import SwiftUI

/// In-place teaser for a locked feature: what it is, then the paywall (P091). Used where hiding the feature would hide
/// that it exists, e.g. below a chart whose forecast is Pro.
struct LockedFeatureCard: View {
    let feature: ProFeature
    @State private var showsPaywall = false

    var body: some View {
        Button { showsPaywall = true } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.fill").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(Self.title(feature)).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    Text(Self.detail(feature)).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text("paywall.seePro").font(DSFont.callout.weight(.semibold)).foregroundStyle(DSColor.accent)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("paywall.seePro.hint"))
        .sheet(isPresented: $showsPaywall) { NavigationStack { PaywallView(feature: feature) } }
        .accessibilityIdentifier("locked-\(feature.rawValue)")
    }

    static func title(_ feature: ProFeature) -> LocalizedStringKey {
        switch feature {
        case .forecast: "gate.forecast.title"
        case .fullInsightHistory: "gate.history.title"
        case .allReferenceGroups: "gate.groups.title"
        case .advancedShareCards: "gate.share.title"
        case .coachUnlimited: "gate.coach.title"
        case .proactiveCoach: "gate.proactive.title"
        }
    }

    static func detail(_ feature: ProFeature) -> LocalizedStringKey {
        switch feature {
        case .forecast: "gate.forecast.detail"
        case .fullInsightHistory: "gate.history.detail"
        case .allReferenceGroups: "gate.groups.detail"
        case .advancedShareCards: "gate.share.detail"
        case .coachUnlimited: "gate.coach.detail"
        case .proactiveCoach: "gate.proactive.detail"
        }
    }
}
