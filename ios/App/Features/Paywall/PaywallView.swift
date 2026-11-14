import DesignSystem
import SwiftUI

/// The subscription paywall (P091): value proposition, plan choice, clear renewal terms, Restore, Terms and Privacy.
/// `feature` is the locked thing that brought the user here; it only changes the headline.
struct PaywallView: View {
    var feature: ProFeature?
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: PaywallModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingState()
            }
        }
        .background(DSColor.background)
        .navigationTitle("paywall.main.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = PaywallModel(purchases: container.purchases) }
            await model?.load()
        }
        .accessibilityIdentifier("paywall")
    }

    @ViewBuilder
    private func content(_ model: PaywallModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                benefits
                if model.isPro {
                    proState(model)
                } else {
                    plans(model)
                    buyButton(model)
                    terms(model)
                }
                footer(model)
            }
            .padding(Spacing.md)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: "bolt.fill").font(.largeTitle).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text(feature.map(Self.headline) ?? "paywall.headline").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            Text("paywall.subtitle").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    static func headline(for feature: ProFeature) -> LocalizedStringKey {
        switch feature {
        case .coachUnlimited: "paywall.headline.coach"
        case .proactiveCoach: "paywall.headline.proactive"
        case .forecast: "paywall.headline.forecast"
        case .fullInsightHistory: "paywall.headline.history"
        case .allReferenceGroups: "paywall.headline.groups"
        case .advancedShareCards: "paywall.headline.share"
        }
    }

    private var benefits: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                benefit("bubble.left.and.text.bubble.right", "paywall.benefit.coach")
                benefit("chart.line.uptrend.xyaxis", "paywall.benefit.forecast")
                benefit("person.3", "paywall.benefit.groups")
                benefit("square.and.arrow.up", "paywall.benefit.share")
            }
        }
        .accessibilityIdentifier("paywall-benefits")
    }

    private func benefit(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: icon).foregroundStyle(DSColor.accent).frame(width: 24).accessibilityHidden(true)
            Text(text).font(DSFont.body).foregroundStyle(DSColor.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func plans(_ model: PaywallModel) -> some View {
        if model.products.isEmpty {
            if model.isLoadingProducts {
                LoadingState()
            } else {
                Text("paywall.plans.unavailable").font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("paywall-plans-unavailable")
            }
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(model.products) { product in planRow(product, model: model) }
            }
        }
    }

    private func planRow(_ product: PurchaseProduct, model: PaywallModel) -> some View {
        let isSelected = model.selected?.id == product.id
        return Button { model.selectedID = product.id } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DSColor.accent : DSColor.textSecondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(product.period == .year ? "paywall.plan.yearly" : "paywall.plan.monthly")
                            .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                        if product.period == .year, let percent = model.yearlySavingsPercent {
                            Text("paywall.plan.save \(percent)").font(DSFont.caption.weight(.semibold)).foregroundStyle(DSColor.accent)
                        }
                    }
                    if product.period == .year, let equivalent = model.yearlyMonthlyEquivalent {
                        Text("paywall.plan.perMonth \(equivalent.formatted(.currency(code: product.currencyCode).locale(locale)))")
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                    if product.isTrialEligible, let days = product.trialDays {
                        Text("paywall.plan.trial \(days)").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Text(verbatim: product.displayPrice).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? DSColor.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(product.period == .year ? "paywall-plan-yearly" : "paywall-plan-monthly")
    }

    private func buyButton(_ model: PaywallModel) -> some View {
        VStack(spacing: Spacing.xs) {
            PrimaryButton(model.trialDays == nil ? "paywall.cta.subscribe" : "paywall.cta.trial", isLoading: model.isBusy) {
                Task { await model.purchase() }
            }
            .disabled(model.selected == nil)
            .accessibilityIdentifier("paywall-buy")
            if let message = model.message {
                Text(Self.text(for: message)).font(DSFont.footnote)
                    .foregroundStyle(message == .pending ? DSColor.textSecondary : DSColor.error)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paywall-message")
            }
        }
    }

    static func text(for message: PaywallModel.Message) -> LocalizedStringKey {
        switch message {
        case .purchaseFailed: "paywall.error.purchase"
        case .pending: "paywall.pending"
        case .restoreNothingFound: "paywall.restore.nothing"
        case .restoreFailed: "paywall.error.restore"
        }
    }

    /// Renewal terms, price after the trial and the way to cancel, as App Review requires them.
    @ViewBuilder
    private func terms(_ model: PaywallModel) -> some View {
        if let product = model.selected {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if model.trialDays != nil, let days = product.trialDays {
                    Text("paywall.terms.trial \(days) \(product.displayPrice) \(periodName(product))")
                } else {
                    Text("paywall.terms.plain \(product.displayPrice) \(periodName(product))")
                }
                Text("paywall.terms.renewal")
                Text("paywall.terms.cancel")
            }
            .font(DSFont.footnote)
            .foregroundStyle(DSColor.textSecondary)
            .accessibilityIdentifier("paywall-terms")
        }
    }

    private func periodName(_ product: PurchaseProduct) -> String {
        product.period == .year ? String(localized: "paywall.period.year") : String(localized: "paywall.period.month")
    }

    private func proState(_ model: PaywallModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("paywall.pro.active", systemImage: "checkmark.seal.fill").font(DSFont.headline).foregroundStyle(DSColor.success)
                if model.entitlements.isTrial { Text("paywall.pro.trial").font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
                if let end = model.entitlements.expiresAt {
                    Text(model.entitlements.willRenew ? "paywall.pro.renews \(end.formatted(date: .abbreviated, time: .omitted))"
                         : "paywall.pro.ends \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                Button("paywall.manage") { Task { await model.manageSubscription() } }
                    .accessibilityIdentifier("paywall-manage")
            }
        }
        .accessibilityIdentifier("paywall-pro-state")
    }

    private func footer(_ model: PaywallModel) -> some View {
        VStack(spacing: Spacing.sm) {
            if !model.isPro {
                Button("paywall.restore") { Task { await model.restore() } }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("paywall-restore")
            }
            HStack(spacing: Spacing.lg) {
                if let terms = LegalLinks.current.terms { Link("auth.legal.terms", destination: terms).accessibilityIdentifier("paywall-terms-link") }
                if let privacy = LegalLinks.current.privacy { Link("auth.legal.privacy", destination: privacy).accessibilityIdentifier("paywall-privacy-link") }
            }
            .font(DSFont.footnote)
        }
        .frame(maxWidth: .infinity)
    }
}
