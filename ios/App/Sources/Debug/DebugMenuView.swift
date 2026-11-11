#if DEBUG
import DesignSystem
import SwiftUI

/// Debug-only developer menu (compiled out of Staging/Release). Grows as tools are added.
struct DebugMenuView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Bileşen Galerisi") { ComponentGalleryView() }
                    .accessibilityIdentifier("debug-gallery-link")
            }
            .navigationTitle("Debug")
        }
    }
}
#endif
