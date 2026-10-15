import XCTest
import ImageIO
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

    func testEndPresentationTimeExtendsDuration() async throws {
        let sink = try GifRecordingSink(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0))
        sink.append(frame(width: 16, height: 16, shade: 0), presentationTime: 50.0)
        sink.append(frame(width: 16, height: 16, shade: 120), presentationTime: 50.1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-tail-\(UUID().uuidString).gif")
        let summary = try await sink.finish(to: url, endPresentationTime: 53.0)
        XCTAssertEqual(summary.durationSecs, 3.0, accuracy: 1e-6)
        try FileManager.default.removeItem(at: url)
    }

    func testDropsFramesWhileTheEncoderIsStalledAndStillWritesAGif() async throws {
        let stalled = DispatchQueue(label: "caniclip.tests.stalled-sink")
        stalled.suspend()
        let sink = try GifRecordingSink(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0),
                                        queue: stalled)
        let extra = 5
        for i in 0..<(GifRecordingSink.maxPending + extra) {
            sink.append(frame(width: 16, height: 16, shade: UInt8(i * 10)), presentationTime: Double(i) / 15.0)
        }
        XCTAssertEqual(sink.droppedFrames, extra, "frames beyond maxPending are dropped while the queue is stalled")
        XCTAssertEqual(sink.acceptedFrames, 0)

        stalled.resume()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-drop-\(UUID().uuidString)-.gif")
        let summary = try await sink.finish(to: url)
        XCTAssertEqual(sink.acceptedFrames, GifRecordingSink.maxPending)
        XCTAssertEqual(summary.frameCount, UInt32(GifRecordingSink.maxPending))
        XCTAssertGreaterThan(sink.droppedFrames, 0)

        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(6), as: UTF8.self), "GIF89a")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(source), 0, "the GIF must still decode")
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try FileManager.default.removeItem(at: url)
    }

    func testFailureCallbackFiresOnceAndStopsAcceptingFrames() async throws {
        let sink = try GifRecordingSink(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0))
        let fired = expectation(description: "onFailure")
        fired.assertForOverFulfill = true
        sink.onFailure = { _ in fired.fulfill() }
        sink.append(frame(width: 16, height: 16, shade: 0), presentationTime: 0.0)
        sink.append(frame(width: 12, height: 16, shade: 10), presentationTime: 0.1)   // size change → encoder error
        sink.append(frame(width: 12, height: 16, shade: 20), presentationTime: 0.2)   // ignored after failure
        await fulfillment(of: [fired], timeout: 5)
        XCTAssertEqual(sink.acceptedFrames, 1)
    }
}
