import CoreGraphics

enum ImageComposer {
    /// Base image with annotations burned in, same pixel size as `base`.
    static func render(base: CGImage, annotations: [Annotation], pixelateImage: (Annotation) -> CGImage?) -> CGImage? {
        let w = base.width, h = base.height
        // Render in the base's own RGB space so a Display P3 screenshot keeps its
        // colours; anything non-RGB (or missing) falls back to sRGB.
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Switch to top-left origin for the annotation space.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(annotations, in: ctx, pixelateImage: pixelateImage)
        return ctx.makeImage()
    }
}
