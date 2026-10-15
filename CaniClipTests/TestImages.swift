import CoreGraphics
import Foundation

enum TestImages {
    static func solid(width: Int, height: Int, color: CGColor) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA of the pixel at (x, y) with (0, 0) the top-left corner.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw the whole image shifted so the wanted pixel lands on the 1x1 context.
        // Context origin is bottom-left, so flip y.
        ctx.interpolationQuality = .none
        let flippedY = image.height - 1 - y
        ctx.draw(image, in: CGRect(x: -x, y: -flippedY, width: image.width, height: image.height))
        return buf
    }
}
