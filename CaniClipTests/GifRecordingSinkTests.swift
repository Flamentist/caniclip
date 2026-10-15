import XCTest
@testable import CaniClip

final class GifRecordingSinkTests: XCTestCase {
    private func frame(width: Int, height: Int, shade: UInt8) -> BGRAFrame {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let on = (x + y + Int(shade)) % 8 < 4
                bytes[i] = on ? shade : 255 &- shade
                bytes[i + 1] = 40
                bytes[i + 2] = on ? 255 &- shade : shade
                bytes[i + 3] = 255
            }
        }
        return BGRAFrame(pixels: Data(bytes), width: width, height: height)
    }

    func testEncodesQueuedFramesIntoGif() async throws {
        let sink = try GifRecordingSink(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0))
        for i in 0..<5 {
            sink.append(frame(width: 32, height: 16, shade: UInt8(i * 30)), presentationTime: 100.0 + Double(i) / 15.0)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-sink-\(UUID().uuidString).gif")
        let summary = try await sink.finish(to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(6), as: UTF8.self), "GIF89a")
        XCTAssertEqual(summary.frameCount, 5)
        XCTAssertEqual(sink.acceptedFrames, 5)
        XCTAssertEqual(sink.droppedFrames, 0)
        XCTAssertEqual(summary.durationSecs, 4.0 / 15.0, accuracy: 1e-6)
        try FileManager.default.removeItem(at: url)
    }

    func testFinishWithoutFramesThrows() async throws {
        let sink = try GifRecordingSink(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-empty-\(UUID().uuidString).gif")
        do {
            _ = try await sink.finish(to: url)
            XCTFail("expected an error")
        } catch {
            guard case CoreError.Encoding = error else { return XCTFail("unexpected \(error)") }
        }
    }
}
