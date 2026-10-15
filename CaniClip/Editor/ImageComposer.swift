import CoreGraphics

enum ImageComposer {
    /// Base image with annotations burned in, same pixel size as `base`.
    static func render(base: CGImage, annotations: [Annotation], pixelateImage: (Annotation) -> CGImage?) -> CGImage? {
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
