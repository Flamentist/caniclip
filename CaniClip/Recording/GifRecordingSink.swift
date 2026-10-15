import Foundation

/// Feeds frames to the Rust GifEncoder on a serial queue. If the encoder falls
/// more than `maxPending` frames behind, new frames are dropped; because every
/// frame carries its real presentation time the GIF's timing stays correct.
final class GifRecordingSink: @unchecked Sendable {
    static let maxPending = 10

    private let encoder: GifEncoder
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingCount = 0
    private var firstTimestamp: Double?
    private var failure: Error?
    private var _accepted = 0
    private var _dropped = 0

    /// Called once, from the encoder queue, the first time a frame fails to encode.
    /// Frames after a failure are ignored; `finish` then throws the same error.
    var onFailure: (@Sendable (Error) -> Void)?

    var acceptedFrames: Int { lock.withLock { _accepted } }
    var droppedFrames: Int { lock.withLock { _dropped } }

    /// `queue` is the serial queue frames are encoded on; tests inject a
    /// suspended one to exercise the back-pressure path.
    init(settings: GifSettings,
         queue: DispatchQueue = DispatchQueue(label: "com.caniclip.gif-sink", qos: .userInitiated)) throws {
        encoder = try GifEncoder(settings: settings)
        self.queue = queue
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
                let first = lock.withLock { () -> Bool in
                    guard failure == nil else { return false }
                    failure = error
                    return true
                }
                if first { onFailure?(error) }
            }
            lock.withLock { pendingCount -= 1 }
        }
    }

    /// Waits for every queued frame, then finalises the GIF at `url`.
    /// `endPresentationTime` (same clock as the frames) holds the last frame until
    /// the moment recording stopped, so a static ending keeps its real length.
    func finish(to url: URL, endPresentationTime: Double? = nil) async throws -> GifSummary {
        let end: Double? = lock.withLock {
            guard let end = endPresentationTime, let first = firstTimestamp else { return nil }
            return end - first
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let failure = lock.withLock({ self.failure }) {
                    encoder.cancel()
                    continuation.resume(throwing: failure)
                    return
                }
                do {
                    continuation.resume(returning: try encoder.finish(outputPath: url.path, endTimestampSecs: end))
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
