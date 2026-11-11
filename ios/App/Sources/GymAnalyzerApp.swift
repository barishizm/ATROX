import DesignSystem
import SwiftUI

@main
struct GymAnalyzerApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
    }
}
