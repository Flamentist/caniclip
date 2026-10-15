import Foundation

/// Feeds frames to the Rust GifEncoder on a serial queue. If the encoder falls
/// more than `maxPending` frames behind, new frames are dropped; because every
/// frame carries its real presentation time the GIF's timing stays correct.
final class GifRecordingSink: @unchecked Sendable {
    static let maxPending = 10

    private let encoder: GifEncoder
    private let queue = DispatchQueue(label: "com.caniclip.gif-sink", qos: .userInitiated)
    private let lock = NSLock()
    private var pendingCount = 0
    private var firstTimestamp: Double?
    private var failure: Error?
    private var _accepted = 0
    private var _dropped = 0

    var acceptedFrames: Int { lock.withLock { _accepted } }
    var droppedFrames: Int { lock.withLock { _dropped } }

    init(settings: GifSettings) throws {
        encoder = try GifEncoder(settings: settings)
    }

    func append(_ frame: BGRAFrame, presentationTime: Double) {
        let timestamp: Double
        lock.lock()
        if failure != nil {
            lock.unlock()
            return
        }
        if pendingCount >= Self.maxPending {
            _dropped += 1
            lock.unlock()
            return
        }
        pendingCount += 1
        if firstTimestamp == nil { firstTimestamp = presentationTime }
        timestamp = presentationTime - (firstTimestamp ?? presentationTime)
        lock.unlock()

        queue.async { [self] in
            do {
                try encoder.addFrame(pixels: frame.pixels, width: UInt32(frame.width), height: UInt32(frame.height),
                                     format: .bgra, timestampSecs: timestamp)
                lock.withLock { _accepted += 1 }
            } catch {
                lock.withLock { failure = error }
            }
            lock.withLock { pendingCount -= 1 }
        }
    }

    /// Waits for every queued frame, then finalises the GIF at `url`.
    func finish(to url: URL) async throws -> GifSummary {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let failure = lock.withLock({ self.failure }) {
                    encoder.cancel()
                    continuation.resume(throwing: failure)
                    return
                }
                do {
                    continuation.resume(returning: try encoder.finish(outputPath: url.path))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in encoder.cancel() }
    }
}
