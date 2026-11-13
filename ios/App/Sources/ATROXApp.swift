import DesignSystem
import SwiftData
import SwiftUI

@main
struct ATROXApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundSync.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
                .modifier(LocalStoreModifier(container: container.modelContainer))
                .task { await container.prepareCatalog() }
                .task { BackgroundSync.shared.coordinator = container.sync }
                .task { await container.checkModelUpdate() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Sync triggers (P045): coming to the foreground syncs and starts the 15-minute timer; leaving stops it.
            switch phase {
            case .active:
                container.sync?.appBecameActive()
                Task { await container.checkModelUpdate() }
            case .background:
                container.sync?.appEnteredBackground()
                BackgroundSync.shared.schedule()
            default: break
            }
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
