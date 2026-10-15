import XCTest
@testable import CaniClip

final class CoreBridgeTests: XCTestCase {
    func testCoreVersionCrossesTheBridge() {
        XCTAssertEqual(coreVersion(), "0.1.0")
    }

    func testPixelateAveragesTwoPixels() throws {
        let input = Data([255, 0, 0, 255, 0, 0, 255, 255])
        let out = try pixelate(pixels: input, width: 2, height: 1, x: 0, y: 0, w: 2, h: 1, blockSize: 2)
        XCTAssertEqual([UInt8](out), [127, 0, 127, 255, 127, 0, 127, 255])
    }

    func testPixelateRejectsBadLength() {
        XCTAssertThrowsError(try pixelate(pixels: Data([1, 2, 3]), width: 2, height: 1, x: 0, y: 0, w: 1, h: 1, blockSize: 1)) { error in
            guard case CoreError.InvalidInput = error else { return XCTFail("unexpected error \(error)") }
        }
    }
}
