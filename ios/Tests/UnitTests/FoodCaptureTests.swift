import Testing
import UIKit

@testable import ATROX

struct FoodImageTests {
    private func photo(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func prepareDownsizesTheUploadAndTheThumbnail() throws {
        let prepared = try #require(FoodImage.prepare(photo(width: 4032, height: 3024)))
        #expect(prepared.jpeg.count <= FoodImage.maxBytes)
        let upload = try #require(UIImage(data: prepared.jpeg))
        #expect(max(upload.size.width, upload.size.height) == 1024)
        let thumbnail = try #require(prepared.thumbnail.flatMap(UIImage.init(data:)))
        #expect(max(thumbnail.size.width, thumbnail.size.height) == 200)
    }

    @Test func smallPhotosAreNotEnlarged() throws {
        let prepared = try #require(FoodImage.prepare(photo(width: 600, height: 400)))
        let upload = try #require(UIImage(data: prepared.jpeg))
        #expect(upload.size == CGSize(width: 600, height: 400))
    }
}

struct MealDictationTests {
    @Test func onlyARealInputFormatCanBeTapped() {
        #expect(MealDictation.isUsable(sampleRate: 44_100, channels: 1))
        // What the input node reports while the microphone is taken (e.g. a phone call).
        #expect(!MealDictation.isUsable(sampleRate: 0, channels: 1))
        #expect(!MealDictation.isUsable(sampleRate: 48_000, channels: 0))
    }
}
