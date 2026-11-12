import DataKit
import DesignSystem
import StrengthKit
import SwiftUI

/// Units, language, theme, notifications (placeholder), privacy and the account actions.
struct SettingsView: View {
    let model: ProfileModel
    let account: AccountModel
    @Environment(AppContainer.self) private var container
    @State private var confirmsSignOut = false
    @AppStorage(WorkoutPreferences.showRirKey) private var showsRir = true
    @AppStorage(WorkoutPreferences.keepAwakeKey) private var keepAwake = true
    @AppStorage(WorkoutPreferences.restAutoStartKey) private var restAutoStart = true
    @AppStorage(WorkoutPreferences.liveActivityKey) private var liveActivity = true

    var body: some View {
        @Bindable var language = container.language
        Form {
            Section("settings.section.preferences") {
                Picker("settings.units", selection: Binding(
                    get: { model.unitSystem }, set: { value in Task { await model.setUnitSystem(value) } }
                )) {
                    Text("onboarding.units.metric").tag(UnitSystem.metric)
                    Text("onboarding.units.imperial").tag(UnitSystem.imperial)
                }
                .accessibilityIdentifier("settings-units")
                Picker("settings.language.title", selection: $language.language) {
                    ForEach(AppLanguage.allCases) { option in
                        if let name = option.nativeName { Text(verbatim: name).tag(option) } else {
                            Text("settings.language.system").tag(option)
                        }
                    }
                }
                .accessibilityIdentifier("settings-language")
                Picker("settings.theme", selection: Binding(
                    get: { container.appearance.theme }, set: { value in Task { await model.setTheme(value) } }
                )) {
                    Text("settings.theme.system").tag(ThemePreference.system)
                    Text("settings.theme.dark").tag(ThemePreference.dark)
                    Text("settings.theme.light").tag(ThemePreference.light)
                }
                .accessibilityIdentifier("settings-theme")
                LabeledContent("settings.notifications") { Text("settings.notifications.soon").foregroundStyle(DSColor.textSecondary) }
            }
            Section("settings.section.workout") {
                Toggle("settings.workout.rir", isOn: $showsRir).accessibilityIdentifier("settings-workout-rir")
                Toggle("settings.workout.keepAwake", isOn: $keepAwake).accessibilityIdentifier("settings-workout-awake")
                Toggle("settings.workout.restAuto", isOn: $restAutoStart).accessibilityIdentifier("settings-workout-rest")
                Toggle("settings.workout.liveActivity", isOn: $liveActivity)
                    .accessibilityIdentifier("settings-workout-live-activity")
                    .onChange(of: liveActivity) { Task { await container.liveActivity?.preferenceChanged() } }
            }
            PlateSettingsSection(unit: model.unitSystem == .imperial ? .pounds : .kilograms)
            privacy
            accountSection
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("account.signOut.confirm", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("account.signOut", role: .destructive) { Task { await container.root.signOut() } }
        }
        .accessibilityIdentifier("settings-screen")
    }

    private var privacy: some View {
        Section {
            Toggle("settings.contribution", isOn: Binding(
                get: { model.isContributing }, set: { value in Task { await model.setContribution(value) } }
            ))
            .accessibilityIdentifier("settings-contribution")
            NavigationLink(value: ProfileRoute.consentHistory) { Text("settings.consentHistory") }
                .accessibilityIdentifier("settings-consent-history")
        } header: {
            Text("settings.section.privacy")
        } footer: {
            Text("settings.contribution.footer")
        }
    }

    private var accountSection: some View {
        Section("settings.section.account") {
            if let email = model.email { LabeledContent("settings.account.email") { Text(verbatim: email) } }
            Button("account.signOut", role: .destructive) { confirmsSignOut = true }
                .accessibilityIdentifier("settings-sign-out")
            exportRow
            NavigationLink(value: ProfileRoute.deleteAccount) {
                Text("account.delete").foregroundStyle(DSColor.error)
            }
            .accessibilityIdentifier("settings-delete-account")
        }
    }

    @ViewBuilder private var exportRow: some View {
        if account.isExporting {
            HStack { Text("account.export.working"); Spacer(); ProgressView() }
        } else if let url = account.exportURL {
            ShareLink(item: url) { Label("account.export.share", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("settings-export-share")
        } else {
            Button("account.export") { Task { await account.export() } }
                .accessibilityIdentifier("settings-export")
            if account.exportFailed {
                Text("account.export.failed").font(DSFont.footnote).foregroundStyle(DSColor.error)
            }
        }
    }
}

/// Every consent decision on record, newest first.
struct ConsentHistoryView: View {
    let model: ProfileModel

    var body: some View {
        List {
            if model.consentHistory.isEmpty {
                Text("consent.history.empty").foregroundStyle(DSColor.textSecondary)
            }
            ForEach(model.consentHistory) { entry in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Self.title(for: entry.kind)
                        Spacer()
                        Text(entry.granted ? "consent.history.granted" : "consent.history.declined")
                            .foregroundStyle(entry.granted ? DSColor.success : DSColor.textSecondary)
                    }
                    HStack(spacing: Spacing.sm) {
                        Text(entry.createdAt, format: .dateTime.day().month().year().hour().minute())
                        Text("consent.history.version \(entry.version)")
                    }
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(DSColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("settings.consentHistory")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("consent-history")
    }

    private static func title(for kind: ConsentKind) -> Text {
        switch kind {
        case .terms: Text("consent.kind.terms")
        case .privacy: Text("consent.kind.privacy")
        case .aiSharing: Text("consent.kind.aiSharing")
        case .mlContribution: Text("consent.kind.mlContribution")
        }
    }
}

/// Default bar and the plates the user owns (used by the plate calculator and warm-up sets).
struct PlateSettingsSection: View {
    let unit: PlateUnit
    @AppStorage(PlatePreferences.barTypeKey) private var barTypeRaw = BarType.olympic20.rawValue
    @AppStorage(PlatePreferences.customBarKgKey) private var customBarKg = 20.0
    @AppStorage(PlatePreferences.ownedKey(.kilograms))
    private var ownedKg = PlatePreferences.encode(PlateDefaults.denominations(for: .kilograms))
    @AppStorage(PlatePreferences.ownedKey(.pounds))
    private var ownedLb = PlatePreferences.encode(PlateDefaults.denominations(for: .pounds))

    private var symbol: String { unit == .kilograms ? "kg" : "lb" }
    private var owned: Binding<String> { unit == .kilograms ? $ownedKg : $ownedLb }

    var body: some View {
        Section {
            Picker("settings.workout.bar", selection: $barTypeRaw) {
                ForEach(BarType.allCases, id: \.rawValue) { type in
                    Text(verbatim: Self.name(type, unit: unit)).tag(type.rawValue)
                }
            }
            .accessibilityIdentifier("settings-bar")
            if barTypeRaw == BarType.custom.rawValue {
                Stepper(value: $customBarKg, in: 0...50, step: 0.5) {
                    Text(verbatim: "\(PlateCalculatorView.format(unit == .kilograms ? customBarKg : customBarKg * 2.2046226218)) \(symbol)")
                }
            }
            ForEach(PlateDefaults.denominations(for: unit), id: \.self) { plate in
                Toggle(isOn: Binding(
                    get: { PlatePreferences.decode(owned.wrappedValue).contains(plate) },
                    set: { isOn in
                        var plates = Set(PlatePreferences.decode(owned.wrappedValue))
                        if isOn { plates.insert(plate) } else { plates.remove(plate) }
                        owned.wrappedValue = PlatePreferences.encode(plates.sorted(by: >))
                    }
                )) {
                    Text(verbatim: "\(PlateCalculatorView.format(plate)) \(symbol)")
                }
            }
        } header: {
            Text("settings.section.plates")
        } footer: {
            Text("settings.plates.footer")
        }
    }

    private static func name(_ type: BarType, unit: PlateUnit) -> String {
        let name = switch type {
        case .olympic20: String(localized: "plates.bar.olympic20")
        case .olympic15: String(localized: "plates.bar.olympic15")
        case .ez: String(localized: "plates.bar.ez")
        case .custom: String(localized: "plates.bar.custom")
        }
        guard let weight = type.weight(in: unit) else { return name }
        return "\(name) · \(PlateCalculatorView.format(weight)) \(unit == .kilograms ? "kg" : "lb")"
    }
}
