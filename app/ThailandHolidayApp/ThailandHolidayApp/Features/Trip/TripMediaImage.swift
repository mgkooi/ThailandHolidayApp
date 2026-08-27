import SwiftUI
import UIKit
import ImageIO

struct TripMediaImage: View {
    @Environment(TripStore.self) private var store
    let media: TripMedia?
    var body: some View {
        Group {
            if let filename = media?.filename,
               let url = store.attachmentURL(for: filename),
               let image = TripImageCache.shared.image(at: url) {
                Image(uiImage: image).resizable()
            } else if let url = media?.remoteURL {
                AsyncImage(url: url) { image in image.resizable() }
                    placeholder: { placeholder }
            } else { placeholder }
        }
    }
    private var placeholder: some View {
        Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
}

private final class TripImageCache: @unchecked Sendable {
    static let shared = TripImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_200
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}
