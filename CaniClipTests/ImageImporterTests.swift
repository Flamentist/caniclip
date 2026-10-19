import XCTest
import UniformTypeIdentifiers
@testable import CaniClip

final class ImageImporterTests: XCTestCase {
    private var folder: URL!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("caniclip.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    private func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil)!
        for image in images { CGImageDestinationAddImage(dest, image, properties as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func gray(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: Files

    func testOpensAPNGFileWithItsNameAsTitle() throws {
        let url = try write(encode([TestImages.solid(width: 40, height: 20, color: red)], type: .png), as: "a.png")
        let imported = try ImageImporter.image(contentsOf: url)
        XCTAssertEqual(imported.image.width, 40)
        XCTAssertEqual(imported.image.height, 20)
        XCTAssertEqual(imported.title, "a.png")
    }

    func testAnimatedGIFOpensAsItsFirstFrame() throws {
        let frames = [TestImages.solid(width: 10, height: 10, color: red), TestImages.solid(width: 10, height: 10, color: blue)]
        let url = try write(encode(frames, type: .gif), as: "anim.gif")
        let pixel = TestImages.pixel(try ImageImporter.image(contentsOf: url).image, x: 5, y: 5)
        XCTAssertGreaterThan(pixel[0], 200)
        XCTAssertLessThan(pixel[2], 60)
    }

    func testCorruptFileThrowsUnreadable() throws {
        let url = try write(Data("nope".utf8), as: "x.png")
        XCTAssertThrowsError(try ImageImporter.image(contentsOf: url)) { error in
            XCTAssertEqual(error as? ImportError, .unreadableFile)
        }
    }

    func testRotatedJPEGOpensUpright() throws {
        let data = encode([TestImages.solid(width: 40, height: 20, color: red)], type: .jpeg,
                          properties: [kCGImagePropertyOrientation: 6])
        let image = try ImageImporter.image(contentsOf: try write(data, as: "phone.jpg")).image
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 40)
    }

    func testOversizedImageIsDownscaledToTheLongSideLimit() throws {
        let url = try write(encode([gray(width: 10_000, height: 6_000)], type: .png), as: "huge.png")
        let image = try ImageImporter.image(contentsOf: url).image
        XCTAssertEqual(image.width, ImageImporter.maxLongSide)
        XCTAssertEqual(Double(image.height), 4915, accuracy: 1)
    }

    func testGrayscaleImageIsNormalisedToRGBA() throws {
        let image = try ImageImporter.image(contentsOf: try write(encode([gray(width: 8, height: 8)], type: .png), as: "g.png")).image
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.colorSpace?.model, .rgb)
        XCTAssertEqual(image.alphaInfo, .premultipliedLast)
    }

    // MARK: Pasteboard

    func testPasteboardFileURLToAnImageWins() throws {
        let url = try write(encode([TestImages.solid(width: 12, height: 6, color: red)], type: .png), as: "shot.png")
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setData(encode([TestImages.solid(width: 3, height: 3, color: blue)], type: .tiff), forType: .tiff)
        let imported = try ImageImporter.image(from: pasteboard)
        XCTAssertEqual(imported.title, "shot.png")
        XCTAssertEqual(imported.image.width, 12)
    }

    func testPasteboardPNGDataIsPastedImage() throws {
        pasteboard.clearContents()
        pasteboard.setData(encode([TestImages.solid(width: 9, height: 7, color: red)], type: .png), forType: .png)
        let imported = try ImageImporter.image(from: pasteboard)
        XCTAssertEqual(imported.title, "Pasted Image")
        XCTAssertEqual(imported.image.width, 9)
        XCTAssertEqual(imported.image.height, 7)
    }

    func testPasteboardTIFFDataIsAccepted() throws {
        pasteboard.clearContents()
        pasteboard.setData(encode([TestImages.solid(width: 5, height: 5, color: blue)], type: .tiff), forType: .tiff)
        XCTAssertEqual(try ImageImporter.image(from: pasteboard).image.width, 5)
    }

    /// Finder puts a copied file's icon on the clipboard as TIFF; that is not the user's image.
    func testPasteboardFileURLToANonImageIsRefusedEvenWithIconData() throws {
        let url = try write(Data("hello".utf8), as: "notes.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setData(encode([TestImages.solid(width: 32, height: 32, color: blue)], type: .tiff), forType: .tiff)
        XCTAssertThrowsError(try ImageImporter.image(from: pasteboard)) { error in
            XCTAssertEqual(error as? ImportError, .noImageOnClipboard)
        }
    }

    func testEmptyPasteboardThrowsNoImage() {
        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        XCTAssertThrowsError(try ImageImporter.image(from: pasteboard)) { error in
            XCTAssertEqual(error as? ImportError, .noImageOnClipboard)
        }
    }
}
