import DesignSystem
import SwiftUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var systemLocale

    var body: some View {
        RootView()
            .environment(\.locale, container.language.effectiveLocale(system: systemLocale))
            .dsRootTheme(container.appearance.preference)
            .accessibilityIdentifier("root")
    }
}
