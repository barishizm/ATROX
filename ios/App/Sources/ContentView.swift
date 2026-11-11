import DesignSystem
import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
            .dsRootTheme()
            .accessibilityIdentifier("root")
    }
}
