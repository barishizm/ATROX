import DesignSystem
import SwiftUI

struct ContentView: View {
    var body: some View {
        Group {
            #if DEBUG
            DebugMenuView()
            #else
            Color.clear
            #endif
        }
        .dsRootTheme()
        .accessibilityIdentifier("root")
    }
}

#Preview {
    ContentView()
}
