import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case encodingFailed
    case writeFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "The image could not be encoded as PNG."
        case .writeFailed(let url, let error): return "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

enum ImageExporter {
    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodingFailed }
        return data as Data
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try writePNG(data: try pngData(from: image), to: url)
    }

    /// Writes already-encoded PNG bytes, so callers that encoded once can reuse them.
    static func writePNG(data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(url, error)
        }
    }

    static func copyToClipboard(_ image: CGImage) {
        let item = NSPasteboardItem()
        if let png = try? pngData(from: image) {
            item.setData(png, forType: .png)
        }
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }

    static func copyFileToClipboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}
