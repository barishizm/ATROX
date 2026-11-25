import UIKit

/// Downsizing for meal photos: what the server needs is a small JPEG (≤ 1.5 MB, long side 1024 px), not the camera original.
/// Pure image work with no UI state: run it off the main actor (`prepare`), a 12 MP photo takes a noticeable moment.
enum FoodImage {
    static let maxBytes = 1_500_000

    /// The upload JPEG and the on-device thumbnail, both made from one downsized copy of the photo.
    struct Prepared: Sendable {
        let jpeg: Data
        let thumbnail: Data?
    }

    static func prepare(_ image: UIImage) -> Prepared? {
        let resized = resize(image, maxDimension: 1024)
        guard let jpeg = jpeg(fromResized: resized) else { return nil }
        return Prepared(jpeg: jpeg, thumbnail: thumbnail(from: resized))
    }

    private static func jpeg(fromResized resized: UIImage) -> Data? {
        var quality: CGFloat = 0.72
        while quality > 0.2 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
            quality -= 0.15
        }
        return resize(resized, maxDimension: 640).jpegData(compressionQuality: 0.5)
    }

    /// A small preview kept on this device with the entry.
    static func thumbnail(from image: UIImage) -> Data? { resize(image, maxDimension: 200).jpegData(compressionQuality: 0.6) }

    /// Also bakes in the orientation, so the model sees the photo upright.
    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        let scale = longSide > maxDimension ? maxDimension / longSide : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
