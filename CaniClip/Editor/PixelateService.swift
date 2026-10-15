import CoreGraphics
import Foundation

/// Produces pixelated crops of the base image through the Rust core, cached per rect.
final class PixelateService {
    private let base: CGImage
    private var cache: [UUID: (rect: CGRect, blockSize: Int, image: CGImage)] = [:]

    init(base: CGImage) {
        self.base = base
    }

    var cachedCount: Int { cache.count }

    /// Drops cached crops for annotations that are no longer in the document.
    func evict(keeping ids: Set<UUID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    func image(for annotation: Annotation) -> CGImage? {
        guard case .pixelate(let rect, let blockSize) = annotation.kind else { return nil }
        let integral = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard integral.width >= 1, integral.height >= 1 else { return nil }
        if let hit = cache[annotation.id], hit.rect == integral, hit.blockSize == blockSize {
            return hit.image
        }
        guard let crop = base.cropping(to: integral) else { return nil }
        let w = crop.width, h = crop.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = try? pixelate(pixels: Data(rgba), width: UInt32(w), height: UInt32(h),
                                      x: 0, y: 0, w: UInt32(w), h: UInt32(h),
                                      blockSize: UInt32(max(1, blockSize))) else { return nil }
        guard let provider = CGDataProvider(data: out as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        cache[annotation.id] = (integral, blockSize, image)
        return image
    }
}
