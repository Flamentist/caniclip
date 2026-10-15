import XCTest
import CoreVideo
@testable import CaniClip

final class FrameConverterTests: XCTestCase {
    private func makeBuffer(width: Int, height: Int, alignment: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferBytesPerRowAlignmentKey: alignment]
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return buffer!
    }

    func testPaddedRowsAreRemoved() {
        let width = 10, height = 3
        let buffer = makeBuffer(width: width, height: height, alignment: 64)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(buffer), width * 4, "test needs a padded buffer")

        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * stride + x * 4
                p[0] = UInt8(x); p[1] = UInt8(y); p[2] = UInt8(x + y); p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let frame = FrameConverter.bgraFrame(from: buffer)!
        XCTAssertEqual(frame.width, width)
        XCTAssertEqual(frame.height, height)
        XCTAssertEqual(frame.pixels.count, width * height * 4)
        let bytes = [UInt8](frame.pixels)
        let i = (2 * width + 9) * 4   // x = 9, y = 2
        XCTAssertEqual(Array(bytes[i..<i + 4]), [9, 2, 11, 255])
        let j = (1 * width + 0) * 4   // x = 0, y = 1
        XCTAssertEqual(Array(bytes[j..<j + 4]), [0, 1, 1, 255])
    }

    func testRejectsNonBGRAFormat() {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32ARGB, nil, &buffer)
        XCTAssertNil(FrameConverter.bgraFrame(from: buffer!))
    }
}
