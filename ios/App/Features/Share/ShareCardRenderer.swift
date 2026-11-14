import SwiftUI
import UIKit

/// Renders a card to an image with `ImageRenderer` (P084). 1× scale of a 1080-wide layout = 1080 px wide.
@MainActor
enum ShareCardRenderer {
    static func image(content: ShareCardContent, options: ShareCardOptions, locale: Locale) -> UIImage? {
        let view = ShareCardView(content: content, options: options).environment(\.locale, locale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(options.format.size)
        return renderer.uiImage
    }
}

/// Direct send to Instagram Stories (P084). Falls back to the share sheet where Instagram is missing.
@MainActor
enum InstagramStories {
    private static let scheme = "instagram-stories://share"

    /// Needs `instagram-stories` in LSApplicationQueriesSchemes.
    static var isAvailable: Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(_ image: UIImage) {
        guard let png = image.pngData(), let url = URL(string: "\(scheme)?source_application=\(Bundle.main.bundleIdentifier ?? "")")
        else { return }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]], options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
    }
}
