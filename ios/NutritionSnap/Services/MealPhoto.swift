import SwiftUI
import UIKit
import ImageIO

/// On-device meal photo storage (free tier; Cloud Storage needs the Blaze plan, deferred to M4).
/// Photos live under Application Support, addressed by filename so they survive relaunches — a
/// reinstall changes the container, so a missing file just falls back to the placeholder.
enum LocalPhotos {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MealPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
}

/// Decodes images to a bounded pixel size via ImageIO so a full-resolution photo (a phone snap is
/// ~12MP ≈ 49MB *once decoded*) is never realized at full size in memory — the app's dominant
/// memory cost and the cause of the jetsam OOM. The compressed JPEG on disk stays small; only the
/// decode is capped. Used on every capture/pick (~1600px, plenty for display + Gemini) and for the
/// far smaller diary thumbnails (~600px).
enum DownsampledImage {
    static func make(from data: Data, maxDimension: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                                                    [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return make(from: src, maxDimension: maxDimension)
    }

    static func make(fromFile url: URL, maxDimension: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                                                   [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return make(from: src, maxDimension: maxDimension)
    }

    private static func make(from source: CGImageSource, maxDimension: CGFloat) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,    // bake in EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Loads + caches meal **thumbnails** by filename for the diary grid + recent-card thumb (≤200pt on
/// screen). Downsampled on load and the cache is bounded — full-res decodes here were the OOM.
@MainActor
final class PhotoCache {
    static let shared = PhotoCache()
    private let cache = NSCache<NSString, UIImage>()
    /// Diary tiles are 104pt and the recent thumb 44pt — 600px covers them sharply at @3x.
    private let thumbnailMaxDimension: CGFloat = 600

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 32 * 1024 * 1024     // ~32MB of decoded thumbnails, then evict
    }

    func image(named name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = DownsampledImage.make(fromFile: LocalPhotos.url(name),
                                                maxDimension: thumbnailMaxDimension) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: image.estimatedByteSize)
        return image
    }

    func remove(named name: String) { cache.removeObject(forKey: name as NSString) }
}

private extension UIImage {
    /// Rough decoded byte size, for NSCache cost accounting.
    var estimatedByteSize: Int {
        guard let cg = cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}

/// A meal photo, with a calm SF-Symbol placeholder while loading or when there's no stored photo
/// (sample data, or a meal whose save didn't land). Reused by the diary + capture.
struct MealPhoto: View {
    /// Local photo filename (from `Entry.photoPath`).
    let path: String?
    var symbol: String = "fork.knife"
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.Palette.accent.opacity(0.12)
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .task(id: path) {
            guard let path else { return }
            image = PhotoCache.shared.image(named: path)
        }
    }
}
