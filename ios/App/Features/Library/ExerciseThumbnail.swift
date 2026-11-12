import DesignSystem
import SwiftUI
import UIKit

/// Loads exercise thumbnails: the copy bundled with the app first, otherwise Supabase Storage with an on-disk
/// cache (P027 naming: `<hash>.t.webp`). Memory-cached; decoding happens off the main thread.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var baseURL: URL?
    private let session: URLSession

    init() {
        let cache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 64 << 20, directory: nil)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 400
    }

    /// `https://<project>.supabase.co/storage/v1/object/public/exercise-images`
    func configure(storageBaseURL: URL?) { baseURL = storageBaseURL }

    func image(named fileName: String) async -> UIImage? {
        let key = fileName as NSString
        if let cached = memory.object(forKey: key) { return cached }
        let stem = (fileName as NSString).deletingPathExtension
        let image: UIImage?
        if let url = Bundle.main.url(forResource: stem, withExtension: "webp") {
            image = UIImage(contentsOfFile: url.path)
        } else if let baseURL, let (data, response) = try? await session.data(from: baseURL.appendingPathComponent(fileName)),
                  (response as? HTTPURLResponse)?.statusCode == 200 {
            image = UIImage(data: data)
        } else {
            image = nil
        }
        if let image { memory.setObject(image, forKey: key) }
        return image
    }
}

struct ExerciseThumbnail: View {
    let fileName: String?
    var size: CGFloat = 56
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            DSColor.surfaceRaised
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityHidden(true)
        .task(id: fileName) {
            guard let fileName else { image = nil; return }
            image = await ThumbnailLoader.shared.image(named: fileName)
        }
    }
}
