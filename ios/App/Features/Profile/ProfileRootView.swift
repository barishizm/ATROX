import DataKit
import DesignSystem
import SwiftUI

/// Profile summary plus the doors to editing, measurements, settings and "about".
struct ProfileRootView: View {
    let model: ProfileModel
    @Environment(\.locale) private var locale
    @Environment(AppContainer.self) private var container
    @State private var look: ProfileLook
    @State private var customizing = false

    init(model: ProfileModel) {
        self.model = model
        _look = State(initialValue: ProfileLook(userId: model.userId))
    }

    /// Asset shown in the hero. Swap this one name when the final characters arrive.
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    subtitle
                    stats
                    if let sync = container.sync, sync.isAvailable { SyncStatusCard(sync: sync) }
                    proBanner
                    friendsRow
                    overview
                }
                .padding(Spacing.md)
                .frame(maxWidth: 560)
            }
            .frame(maxWidth: .infinity)
        }
        .background(DSColor.background)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $customizing) { ProfileCustomizeSheet(look: look) }
        .accessibilityIdentifier("profile-root")
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .top) {
            look.color.color
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(look.mascot.rawValue)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 190)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, Spacing.md)
            ZStack {
                Group {
                    if let name = model.displayName {
                        Text(verbatim: name)
                    } else {
                        Text("profile.summary.noName")
                    }
                }
                .font(DSFont.title)
                .foregroundStyle(look.color.onColor)
                .lineLimit(1)
                .padding(.horizontal, 64)
                .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button { customizing = true } label: { heroIcon("paintpalette") }
                        .accessibilityLabel("profile.customize.title")
                        .accessibilityIdentifier("profile-customize")
                    NavigationLink(value: ProfileRoute.settings) { heroIcon("gearshape") }
                        .accessibilityLabel("profile.row.settings")
                        .accessibilityIdentifier("profile-settings")
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, 56)
        }
        .frame(height: 340)
    }

    private func heroIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(look.color.onColor)
            .frame(width: HitTarget.minimum, height: HitTarget.minimum)
    }

    private var subtitle: some View {
        HStack(spacing: Spacing.xs) {
            if let email = model.email { Text(verbatim: email.uppercased()) }
            if let year = model.profile?.createdAt.formatted(.dateTime.year().locale(locale)) {
                Text(verbatim: "·")
                Text("profile.joined \(year)")
            }
        }
        .font(DSFont.overline)
        .foregroundStyle(DSColor.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Sections

    private var proBanner: some View {
        NavigationLink(value: ProfileRoute.paywall) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "bolt.fill").font(.title2).accessibilityHidden(true)
                Text("profile.row.pro").font(DSFont.headline)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .foregroundStyle(DSColor.onHighlight)
            .padding(Spacing.md)
            .frame(minHeight: HitTarget.button)
            .background(DSColor.highlightFill, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-pro")
    }

    /// The friends screen had no way in except an invite link.
    private var friendsRow: some View {
        NavigationLink(value: ProfileRoute.social) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.2").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                Text("social.friends.title").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(minHeight: HitTarget.button)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-friends")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("profile.overview").dsOverline()
            if let change = model.weightChangeKg {
                let unit = model.weightUnit
                HStack(spacing: Spacing.sm) {
                    Image(systemName: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .foregroundStyle(DSColor.highlight).accessibilityHidden(true)
                    Text("profile.stat.weight").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    Text(verbatim: unit.value(fromKilograms: change)
                        .formatted(.number.sign(strategy: .always()).precision(.fractionLength(0...1)).locale(locale)) + " " + unit.symbol)
                        .font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
                }
            }
            HStack(spacing: Spacing.sm) {
                Image(systemName: "scalemass").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                Text("profile.row.measurements").font(DSFont.body).foregroundStyle(DSColor.textSecondary)
                Spacer()
                Text(verbatim: "\(model.measurements.count)").font(DSFont.numericMedium).foregroundStyle(DSColor.textPrimary)
            }
        }
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
}
