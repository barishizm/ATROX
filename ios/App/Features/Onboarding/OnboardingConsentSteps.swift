import DataKit
import DesignSystem
import SwiftUI

// MARK: Terms and privacy

/// Terms + privacy: two links and one button. Accepting is recorded as `ConsentRecord`s with their versions.
struct TermsStepView: View {
    @Bindable var model: OnboardingViewModel
    var legal: LegalLinks = .current

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPage(title: "onboarding.terms.title", subtitle: "onboarding.terms.subtitle") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    linkRow(
                        "onboarding.terms.termsLink", systemImage: "doc.text", url: legal.terms, id: "onboarding-terms-link"
                    )
                    linkRow(
                        "onboarding.terms.privacyLink", systemImage: "lock.shield", url: legal.privacy,
                        id: "onboarding-privacy-link"
                    )
                    Text("onboarding.terms.age")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            ConsentFooter(model: model) {
                PrimaryButton("onboarding.terms.accept", isLoading: model.isSaving) {
                    Task { await model.acceptLegal() }
                }
                .accessibilityIdentifier("onboarding-terms-accept")
            }
        }
    }

    /// A missing URL (fresh clone without xcconfig values) leaves a plain label instead of a dead link.
    @ViewBuilder
    private func linkRow(_ title: LocalizedStringKey, systemImage: String, url: URL?, id: String) -> some View {
        let label = HStack(spacing: Spacing.md) {
            Image(systemName: systemImage).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            if url != nil {
                Image(systemName: "arrow.up.right").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        Card {
            if let url {
                Link(destination: url) { label.frame(minHeight: HitTarget.minimum) }
                    .accessibilityIdentifier(id)
            } else {
                label.frame(minHeight: HitTarget.minimum)
            }
        }
    }
}

// MARK: Model contribution

/// "Modeli birlikte geliştirelim": opt-in, no pre-ticked box. The primary button is the only way to say yes.
struct ContributionStepView: View {
    @Bindable var model: OnboardingViewModel
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPage(title: "onboarding.contribution.title", subtitle: "onboarding.contribution.subtitle") {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        assurance("person.crop.circle.badge.xmark", "onboarding.contribution.assure.identity")
                        assurance("chart.bar.xaxis", "onboarding.contribution.assure.data")
                        assurance("switch.2", "onboarding.contribution.assure.anytime")
                    }
                    details
                }
            }
            ConsentFooter(model: model) {
                PrimaryButton("onboarding.contribution.accept", isLoading: model.isSaving) {
                    Task { await model.decideContribution(true) }
                }
                .accessibilityIdentifier("onboarding-contribution-accept")
                Button {
                    Task { await model.decideContribution(false) }
                } label: {
                    Text("onboarding.contribution.skip")
                        .font(DSFont.callout.weight(.semibold))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                }
                .disabled(model.isSaving)
                .accessibilityIdentifier("onboarding-contribution-skip")
            }
        }
    }

    private func assurance(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)
            Text(text).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
        }
    }

    /// Exactly what leaves the device (docs/02-MIMARI.md §3.3), and what never does.
    private var details: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("onboarding.contribution.details.intro").font(DSFont.footnote)
                ForEach(Self.sharedFields, id: \.self) { field in
                    bullet(LocalizedStringKey(field), systemImage: "checkmark")
                }
                Text("onboarding.contribution.details.neverTitle").font(DSFont.footnote.weight(.semibold))
                    .padding(.top, Spacing.xs)
                ForEach(Self.neverShared, id: \.self) { field in
                    bullet(LocalizedStringKey(field), systemImage: "xmark")
                }
                Text("onboarding.contribution.details.cadence").font(DSFont.footnote).padding(.top, Spacing.xs)
            }
            .foregroundStyle(DSColor.textSecondary)
            .padding(.top, Spacing.sm)
        } label: {
            Text("onboarding.contribution.details.title")
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
        }
        .tint(DSColor.textSecondary)
        .accessibilityIdentifier("onboarding-contribution-details")
    }

    private func bullet(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: systemImage).font(DSFont.caption).frame(width: 16).accessibilityHidden(true)
            Text(text).font(DSFont.footnote)
        }
    }

    private static let sharedFields: [String] = [
        "onboarding.contribution.field.sex",
        "onboarding.contribution.field.age",
        "onboarding.contribution.field.weight",
        "onboarding.contribution.field.height",
        "onboarding.contribution.field.experience",
        "onboarding.contribution.field.frequency",
        "onboarding.contribution.field.lifts",
        "onboarding.contribution.field.month",
        "onboarding.contribution.field.key",
    ]

    private static let neverShared: [String] = [
        "onboarding.contribution.never.name",
        "onboarding.contribution.never.account",
        "onboarding.contribution.never.notes",
    ]
}

// MARK: Shared

/// Bottom bar of a consent screen: optional save error above the buttons.
private struct ConsentFooter<Buttons: View>: View {
    let model: OnboardingViewModel
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if model.saveFailed {
                Text("onboarding.saveError")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.error)
                    .accessibilityIdentifier("onboarding-save-error")
            }
            buttons
        }
        .padding(Spacing.lg)
        .frame(maxWidth: 520)
    }
}
