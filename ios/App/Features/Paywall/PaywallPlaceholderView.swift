import SwiftUI

/// Subscription paywall (real screens: P091).
struct PaywallPlaceholderView: View {
    var body: some View {
        FeaturePlaceholderView(title: "paywall.main.title", systemImage: "star")
            .navigationTitle("paywall.main.title")
    }
}
