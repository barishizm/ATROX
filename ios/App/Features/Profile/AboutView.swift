import DesignSystem
import SwiftUI

/// App version, scoring-model version (placeholder until the model download lands) and the licenses screen.
struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("about.version") { Text(verbatim: Self.versionString) }
                    .accessibilityIdentifier("about-version")
                LabeledContent("about.model") { Text("about.model.none").foregroundStyle(DSColor.textSecondary) }
                NavigationLink(value: ProfileRoute.licenses) { Text("about.licenses") }
                    .accessibilityIdentifier("about-licenses")
            }
            .listRowBackground(DSColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("about.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("about-screen")
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// Third-party components the app ships with. Add a row here whenever a dependency or dataset is added.
struct LicenseEntry: Identifiable, Equatable {
    let name: String
    let license: String
    let url: URL
    var id: String { name }

    static let all: [LicenseEntry] = [
        LicenseEntry(name: "supabase-swift", license: "MIT", url: URL(string: "https://github.com/supabase/supabase-swift")!),
        LicenseEntry(name: "GoogleSignIn-iOS", license: "Apache-2.0", url: URL(string: "https://github.com/google/GoogleSignIn-iOS")!),
    ]
}

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                ForEach(LicenseEntry.all) { entry in
                    Link(destination: entry.url) {
                        LabeledContent {
                            Text(verbatim: entry.license).foregroundStyle(DSColor.textSecondary)
                        } label: {
                            Text(verbatim: entry.name).foregroundStyle(DSColor.textPrimary)
                        }
                    }
                }
            } footer: {
                Text("about.licenses.footer")
            }
            .listRowBackground(DSColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("about.licenses")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("licenses-screen")
    }
}
