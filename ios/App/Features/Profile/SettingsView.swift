import DataKit
import DesignSystem
import SwiftUI

/// Units, language, theme, notifications (placeholder), privacy and the account actions.
struct SettingsView: View {
    let model: ProfileModel
    let account: AccountModel
    @Environment(AppContainer.self) private var container
    @State private var confirmsSignOut = false
    @AppStorage(WorkoutPreferences.showRirKey) private var showsRir = true
    @AppStorage(WorkoutPreferences.keepAwakeKey) private var keepAwake = true

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
            }
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
