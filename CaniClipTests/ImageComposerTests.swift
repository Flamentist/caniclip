import XCTest
@testable import CaniClip

final class ImageComposerTests: XCTestCase {
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    func testOutputKeepsBaseSizeAndUntouchedPixels() {
        let base = TestImages.solid(width: 40, height: 30, color: blue)
        let rect = Annotation(kind: .rect(CGRect(x: 4, y: 4, width: 12, height: 12)),
                              style: AnnotationStyle(color: .red, strokeWidth: 2, fontSize: 24))
        let out = ImageComposer.render(base: base, annotations: [rect], pixelateImage: { _ in nil })!
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 30)
        XCTAssertEqual(TestImages.pixel(out, x: 35, y: 25), [0, 0, 255, 255])
    }

    func testRectStrokeIsDrawnAtTopLeftOriginCoordinates() {
        let base = TestImages.solid(width: 40, height: 30, color: blue)
        let rect = Annotation(kind: .rect(CGRect(x: 4, y: 4, width: 12, height: 12)),
                              style: AnnotationStyle(color: .red, strokeWidth: 2, fontSize: 24))
        let out = ImageComposer.render(base: base, annotations: [rect], pixelateImage: { _ in nil })!
        let onStroke = TestImages.pixel(out, x: 4, y: 10)       // left edge, near the top of the image
        XCTAssertGreaterThan(onStroke[0], 200, "expected red on the stroke, got \(onStroke)")
        let interior = TestImages.pixel(out, x: 10, y: 10)
        XCTAssertEqual(interior, [0, 0, 255, 255])
        // Nothing should be drawn near the bottom-left, which is where an unflipped context would put it.
        XCTAssertEqual(TestImages.pixel(out, x: 4, y: 24), [0, 0, 255, 255])
    }

    func testOutputKeepsTheBaseColorSpace() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: p3, components: [1, 0, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let base = ctx.makeImage()!
        XCTAssertEqual(base.colorSpace?.name, CGColorSpace.displayP3)

        let out = ImageComposer.render(base: base, annotations: [], pixelateImage: { _ in nil })!
        XCTAssertEqual(out.colorSpace?.name, CGColorSpace.displayP3,
                       "a P3 screenshot must not be re-rendered into sRGB")
    }

    func testPixelateServiceAveragesRegionViaRust() {
        // Left half red, right half blue; pixelating the whole thing with one block gives purple-ish.
        let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        ctx.setFillColor(blue)
        ctx.fill(CGRect(x: 4, y: 0, width: 4, height: 4))
        let base = ctx.makeImage()!
        let service = PixelateService(base: base)
        let ann = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 8, height: 4), blockSize: 8))
        let img = service.image(for: ann)!
        XCTAssertEqual(img.width, 8)
        XCTAssertEqual(img.height, 4)
        let p = TestImages.pixel(img, x: 1, y: 1)
        XCTAssertEqual(p[0], 127, accuracy: 2)
        XCTAssertEqual(p[2], 127, accuracy: 2)
        XCTAssertEqual(TestImages.pixel(img, x: 7, y: 3), p)
    }

    func testPixelateOnTopBottomSplitKeepsEachHalfUpright() {
        // Top half red, bottom half blue (in top-left image coordinates). Pixelating
        // with blocks the size of each half must leave red on top and blue below,
        // both in the service's crop and in the composed output: a vertical flip
        // anywhere in the pipeline would swap them.
        let w = 4, h = 8
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 4, width: w, height: 4))   // CG origin is bottom-left: y 4..8 is the top half
        ctx.setFillColor(blue)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 4))
        let base = ctx.makeImage()!
        XCTAssertEqual(TestImages.pixel(base, x: 1, y: 1), [255, 0, 0, 255])
        XCTAssertEqual(TestImages.pixel(base, x: 1, y: 6), [0, 0, 255, 255])

        let service = PixelateService(base: base)
        let ann = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: w, height: h), blockSize: 4))
        let crop = service.image(for: ann)!
        XCTAssertEqual(TestImages.pixel(crop, x: 1, y: 1), [255, 0, 0, 255])
        XCTAssertEqual(TestImages.pixel(crop, x: 1, y: 6), [0, 0, 255, 255])

        let out = ImageComposer.render(base: base, annotations: [ann]) { service.image(for: $0) }!
        XCTAssertEqual(TestImages.pixel(out, x: 2, y: 0), [255, 0, 0, 255])
        XCTAssertEqual(TestImages.pixel(out, x: 2, y: 3), [255, 0, 0, 255])
        XCTAssertEqual(TestImages.pixel(out, x: 2, y: 4), [0, 0, 255, 255])
        XCTAssertEqual(TestImages.pixel(out, x: 2, y: 7), [0, 0, 255, 255])
    }
}

final class AnnotationRendererScaleTests: XCTestCase {
    /// Draws into a context whose user space is scaled by `scale`, the way the
    /// on-screen canvas does for a zoomed or Retina view.
    private func render(_ annotations: [Annotation], scale: CGFloat, size: CGSize) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        AnnotationRenderer.draw(annotations, in: ctx, pixelateImage: { _ in nil })
        return ctx.makeImage()!
    }

    func testScaledContextDrawsTheSameStrokeAsUnscaled() {
        let rect = Annotation(kind: .rect(CGRect(x: 4, y: 4, width: 12, height: 12)),
                              style: AnnotationStyle(color: .red, strokeWidth: 2, fontSize: 24))
        let size = CGSize(width: 40, height: 30)
        let one = render([rect], scale: 1, size: size)
        let two = render([rect], scale: 2, size: size)
        XCTAssertEqual(two.width, one.width * 2)

        // Sanity: the stroke is actually there in the unscaled render.
        let onStroke = TestImages.pixel(one, x: 3, y: 10)
        XCTAssertGreaterThan(onStroke[0], 200, "expected red on the stroke, got \(onStroke)")
        XCTAssertLessThan(onStroke[1], 100)
        XCTAssertEqual(TestImages.pixel(one, x: 10, y: 10), [255, 255, 255, 255])

        // Every unscaled pixel on the sampled rows and columns must equal the
        // 2x2 block it maps to in the scaled render.
        for y in [4, 10, 15] {
            for x in 0..<Int(size.width) {
                let expected = TestImages.pixel(one, x: x, y: y)
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    XCTAssertEqual(TestImages.pixel(two, x: 2 * x + dx, y: 2 * y + dy), expected,
                                   "mismatch at (\(x), \(y)) offset (\(dx), \(dy))")
                }
            }
        }
        for x in [4, 10, 15] {
            for y in 0..<Int(size.height) {
                let expected = TestImages.pixel(one, x: x, y: y)
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    XCTAssertEqual(TestImages.pixel(two, x: 2 * x + dx, y: 2 * y + dy), expected,
                                   "mismatch at (\(x), \(y)) offset (\(dx), \(dy))")
                }
            }
        }
    }
}
