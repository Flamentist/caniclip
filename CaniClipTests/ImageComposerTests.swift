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
}
