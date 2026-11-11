import SwiftUI

extension View {
    /// Preview wrapper: scheme + Dynamic Type size on the themed background.
    func dsPreview(_ scheme: ColorScheme, type: DynamicTypeSize = .large) -> some View {
        ScrollView {
            self.padding(Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
        .environment(\.dynamicTypeSize, type)
        .preferredColorScheme(scheme)
    }
}
