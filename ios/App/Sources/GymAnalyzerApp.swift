import DesignSystem
import SwiftData
import SwiftUI

@main
struct GymAnalyzerApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
                .modifier(LocalStoreModifier(container: container.modelContainer))
        }
    }
}

/// Injects the SwiftData container into the view tree when one exists.
private struct LocalStoreModifier: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container { content.modelContainer(container) } else { content }
    }
}
