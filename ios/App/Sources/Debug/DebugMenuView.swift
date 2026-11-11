#if DEBUG
import DesignSystem
import SwiftUI

/// Debug-only developer menu (compiled out of Staging/Release). Grows as tools are added.
struct DebugMenuView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("debug.menu.gallery") { ComponentGalleryView() }
                    .accessibilityIdentifier("debug-gallery-link")
                NavigationLink("debug.menu.localization") { LocalizationDebugView() }
                    .accessibilityIdentifier("debug-l10n-link")
            }
            .navigationTitle("debug.menu.title")
        }
    }
}
#endif
