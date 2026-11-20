import DesignSystem
import Observation
import SwiftUI

/// Rainbow backgrounds for the profile hero. Blue is the brand colour and the default.
enum HeroColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, indigo, violet

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: Color(red: 0.90, green: 0.28, blue: 0.30)
        case .orange: Color(red: 0.996, green: 0.522, blue: 0.0)
        case .yellow: Color(red: 1.0, green: 0.80, blue: 0.10)
        case .green: Color(red: 0.18, green: 0.69, blue: 0.36)
        case .blue: DSColor.accentFill
        case .indigo: Color(red: 0.30, green: 0.30, blue: 0.86)
        case .violet: Color(red: 0.56, green: 0.31, blue: 0.85)
        }
    }

    /// Text and icon colour that stays readable on `color`.
    var onColor: Color { self == .yellow ? Color(red: 0.13, green: 0.14, blue: 0.18) : .white }

    var name: LocalizedStringKey {
        switch self {
        case .red: "profile.color.red"
        case .orange: "profile.color.orange"
        case .yellow: "profile.color.yellow"
        case .green: "profile.color.green"
        case .blue: "profile.color.blue"
        case .indigo: "profile.color.indigo"
        case .violet: "profile.color.violet"
        }
    }
}

/// Face expressions of the hero mascot. Each case is an asset name; add a case (and an asset) for a new character.
enum HeroMascot: String, CaseIterable, Identifiable {
    case cool = "MascotCool"
    case happy = "MascotHappy"
    case excited = "MascotExcited"
    case welcome = "MascotWelcome"

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .cool: "profile.mascot.cool"
        case .happy: "profile.mascot.happy"
        case .excited: "profile.mascot.excited"
        case .welcome: "profile.mascot.welcome"
        }
    }
}

/// The user's profile-look choices, kept on this device per user.
@MainActor
@Observable
final class ProfileLook {
    var color: HeroColor { didSet { defaults.set(color.rawValue, forKey: key("color")) } }
    var mascot: HeroMascot { didSet { defaults.set(mascot.rawValue, forKey: key("mascot")) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let userId: UUID

    init(userId: UUID, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
        let prefix = "profile.look.\(userId.uuidString)."
        color = defaults.string(forKey: prefix + "color").flatMap(HeroColor.init(rawValue:)) ?? .blue
        mascot = defaults.string(forKey: prefix + "mascot").flatMap(HeroMascot.init(rawValue:)) ?? .cool
    }

    private func key(_ name: String) -> String { "profile.look.\(userId.uuidString).\(name)" }
}

/// Sheet to pick the hero colour and mascot expression, with a live preview.
struct ProfileCustomizeSheet: View {
    @Bindable var look: ProfileLook
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ZStack {
                        look.color.color
                        Image(look.mascot.rawValue).resizable().scaledToFit().padding(Spacing.md)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .accessibilityHidden(true)

                    Text("profile.customize.color").dsOverline()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 7), spacing: Spacing.sm) {
                        ForEach(HeroColor.allCases) { option in
                            Button { look.color = option } label: {
                                Circle().fill(option.color)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if look.color == option {
                                            Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(option.onColor)
                                        }
                                    }
                                    .frame(minHeight: HitTarget.minimum)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                            .accessibilityAddTraits(look.color == option ? .isSelected : [])
                            .accessibilityIdentifier("profile-color-\(option.rawValue)")
                        }
                    }

                    Text("profile.customize.mascot").dsOverline()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 4), spacing: Spacing.sm) {
                        ForEach(HeroMascot.allCases) { option in
                            Button { look.mascot = option } label: {
                                Image(option.rawValue).resizable().scaledToFit()
                                    .padding(Spacing.xs)
                                    .frame(height: 72)
                                    .background(DSColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                            .stroke(look.mascot == option ? DSColor.accent : DSColor.separator, lineWidth: look.mascot == option ? 3 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                            .accessibilityAddTraits(look.mascot == option ? .isSelected : [])
                            .accessibilityIdentifier("profile-mascot-\(option.rawValue)")
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(DSColor.background)
            .navigationTitle("profile.customize.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("profile.customize.done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
