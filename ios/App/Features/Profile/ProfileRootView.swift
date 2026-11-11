import DataKit
import DesignSystem
import SwiftUI

/// Profile summary plus the doors to editing, measurements, settings and "about".
struct ProfileRootView: View {
    let model: ProfileModel
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                stats
                VStack(spacing: Spacing.sm) {
                    row("profile.row.edit", icon: "person.text.rectangle", route: .editProfile, id: "profile-edit")
                    row("profile.row.measurements", icon: "scalemass", route: .measurements, id: "profile-measurements")
                    row("profile.row.settings", icon: "gearshape", route: .settings, id: "profile-settings")
                    row("profile.row.about", icon: "info.circle", route: .about, id: "profile-about")
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(DSColor.background)
        .accessibilityIdentifier("profile-root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let name = model.displayName {
                Text(verbatim: name).font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            } else {
                Text("profile.summary.noName").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
            }
            if let email = model.email {
                Text(verbatim: email).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var stats: some View {
        HStack(spacing: Spacing.sm) {
            if let kg = model.latestWeightKg {
                let unit = model.weightUnit
                StatTile(
                    "profile.stat.weight",
                    value: unit.value(fromKilograms: kg).formatted(.number.precision(.fractionLength(0...1)).locale(locale)),
                    unit: unit.symbol
                )
            } else {
                StatTile("profile.stat.weight", value: "–")
            }
            if let height = model.profile?.input.heightCm {
                switch model.lengthUnit {
                case .centimeters: StatTile("profile.stat.height", value: height.formatted(.number.precision(.fractionLength(0))), unit: "cm")
                case .feetInches: StatTile("profile.stat.height", value: LengthFormat.string(centimeters: height, unit: .feetInches, locale: locale))
                }
            }
            if let age = model.age {
                StatTile("profile.stat.age", value: "\(age)")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, icon: String, route: ProfileRoute, id: String) -> some View {
        NavigationLink(value: route) {
            Card {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon).foregroundStyle(DSColor.accent).frame(width: 28).accessibilityHidden(true)
                    Text(title).font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right").font(DSFont.footnote).foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: HitTarget.minimum)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
