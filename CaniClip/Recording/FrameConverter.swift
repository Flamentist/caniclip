import CoreVideo
import Foundation

/// A tightly packed 32-bit BGRA frame (no row padding).
struct BGRAFrame {
    let pixels: Data
    let width: Int
    let height: Int
}

enum FrameConverter {
    /// Copies a 32BGRA pixel buffer into a packed buffer, removing any row stride padding.
    static func bgraFrame(from buffer: CVPixelBuffer) -> BGRAFrame? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let rowBytes = width * 4
        var data = Data(count: rowBytes * height)
        data.withUnsafeMutableBytes { dst in
            guard let out = dst.baseAddress else { return }
            if stride == rowBytes {
                memcpy(out, base, rowBytes * height)
            } else {
                for y in 0..<height {
                    memcpy(out + y * rowBytes, base + y * stride, rowBytes)
                }
            }
        }
        return BGRAFrame(pixels: data, width: width, height: height)
    }
}
