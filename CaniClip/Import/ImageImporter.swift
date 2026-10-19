import AppKit
import ImageIO
import UniformTypeIdentifiers

/// An image brought in from outside CaniClip, ready for the editor.
struct ImportedImage {
    let image: CGImage
    /// The file's name, or "Pasted Image"; used as the editor's window title.
    let title: String
}

enum ImportError: LocalizedError, Equatable {
    case noImageOnClipboard
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .noImageOnClipboard: return "There's no image on the clipboard"
        case .unreadableFile: return "CaniClip can't open this file"
        }
    }
}

/// Turns files, image data and the clipboard into upright 8-bit sRGB images,
/// shrinking very large ones so the editor stays responsive.
enum ImageImporter {
    static let maxPixels = 50_000_000
    static let maxLongSide = 8192

    static func image(contentsOf url: URL) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImportError.unreadableFile }
        return ImportedImage(image: try decode(source), title: url.lastPathComponent)
    }

    static func image(from data: Data, title: String) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImportError.unreadableFile }
        return ImportedImage(image: try decode(source), title: title)
    }

    /// File URLs win over image data. When the clipboard holds files but none is an
    /// image, it is refused: Finder adds the file's icon as TIFF, which isn't the user's image.
    static func image(from pasteboard: NSPasteboard) throws -> ImportedImage {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            guard let url = urls.first(where: isImageFile) else { throw ImportError.noImageOnClipboard }
            return try image(contentsOf: url)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let imported = try? image(from: data, title: "Pasted Image") {
                return imported
            }
        }
        if let ns = NSImage(pasteboard: pasteboard), let tiff = ns.tiffRepresentation,
           let imported = try? image(from: tiff, title: "Pasted Image") {
            return imported
        }
        throw ImportError.noImageOnClipboard
    }

    static func isImageFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image)
            ?? UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    // MARK: Decoding

    private static func decode(_ source: CGImageSource) throws -> CGImage {
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImportError.unreadableFile }
        let longSide = max(width, height)
        let limit = width * height > maxPixels ? min(longSide, maxLongSide) : longSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImportError.unreadableFile
        }
        return try normalized(decoded)
    }

    /// Redraws into 8-bit sRGB with premultiplied alpha, the format the editor,
    /// pixelation and export expect, whatever the file used (gray, 16-bit, CMYK).
    private static func normalized(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ImportError.unreadableFile }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = ctx.makeImage() else { throw ImportError.unreadableFile }
        return out
    }
}
