import DesignSystem
import SwiftUI

/// Stand-in screen for features that are not built yet.
struct FeaturePlaceholderView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        EmptyState(systemImage: systemImage, title: title, message: "placeholder.message")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.background)
    }
}
