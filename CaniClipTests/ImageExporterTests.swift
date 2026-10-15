import XCTest
@testable import CaniClip

final class ImageExporterTests: XCTestCase {
    static func makeImage(width: Int, height: Int, fill: CGColor) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(fill)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testPNGDataHasSignature() throws {
        let img = Self.makeImage(width: 2, height: 2, fill: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let data = try ImageExporter.pngData(from: img)
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testWriteToMissingFolderThrowsWriteFailed() {
        let img = Self.makeImage(width: 2, height: 2, fill: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        let url = URL(fileURLWithPath: "/nonexistent-caniclip-\(UUID().uuidString)/x.png")
        XCTAssertThrowsError(try ImageExporter.writePNG(img, to: url)) { error in
            guard case ExportError.writeFailed = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testWritePNGCreatesFile() throws {
        let img = Self.makeImage(width: 3, height: 3, fill: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-\(UUID().uuidString).png")
        try ImageExporter.writePNG(img, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: url)
    }
}
