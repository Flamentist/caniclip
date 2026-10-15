import AppKit
import Combine

/// App-managed capture history: an index plus screenshot copies and thumbnails
/// under Application Support. Never touches files in the user's save folder.
@MainActor
final class CaptureLibrary: ObservableObject {
    enum LibraryError: LocalizedError {
        case encodeFailed
        case recordNotFound

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return "The image could not be encoded for the history."
            case .recordNotFound: return "That capture is no longer in the history."
            }
        }
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CaniClip/Library", isDirectory: true)
    }

    static let shared = CaptureLibrary(rootURL: defaultRoot)

    @Published private(set) var records: [CaptureRecord] = []
    let rootURL: URL

    private let fm = FileManager.default
    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }
    private var assetsURL: URL { rootURL.appendingPathComponent("assets", isDirectory: true) }
    private var thumbsURL: URL { rootURL.appendingPathComponent("thumbs", isDirectory: true) }

    init(rootURL: URL) {
        self.rootURL = rootURL
        records = Self.load(from: rootURL.appendingPathComponent("index.json"))
    }

    // MARK: Paths

    func assetURL(for id: UUID) -> URL { assetsURL.appendingPathComponent("\(id.uuidString).png") }
    func thumbnailURL(for id: UUID) -> URL { thumbsURL.appendingPathComponent("\(id.uuidString).jpg") }

    /// The saved file if it still exists, else the library copy, else nil.
    func bestFileURL(for record: CaptureRecord) -> URL? {
        if let path = record.savedPath, fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let asset = assetURL(for: record.id)
        if record.hasLibraryAsset, fm.fileExists(atPath: asset.path) {
            return asset
        }
        return nil
    }

    // MARK: Mutations

    @discardableResult
    func addScreenshot(_ image: CGImage, pngData: Data? = nil) throws -> CaptureRecord {
        try ensureDirectories()
        let id = UUID()
        let png = try pngData ?? ImageExporter.pngData(from: image)
        guard !png.isEmpty else { throw LibraryError.encodeFailed }
        let record = CaptureRecord(id: id, kind: .screenshot, createdAt: Date(),
                                   pixelWidth: image.width, pixelHeight: image.height,
                                   fileSizeBytes: Int64(png.count), savedPath: nil,
                                   hasLibraryAsset: true, durationSeconds: nil, frameCount: nil)
        do {
            try png.write(to: assetURL(for: id), options: .atomic)
            try writeThumbnail(of: image, id: id)
            try commit([record] + records)
        } catch {
            // Never leave files behind for a record that was not persisted.
            removeFiles(for: id)
            throw error
        }
        return record
    }

    @discardableResult
    func addGif(url: URL, summary: GifSummary?) throws -> CaptureRecord {
        try ensureDirectories()
        let id = UUID()
        let size = ThumbnailMaker.pixelSize(ofImageAt: url) ?? .zero
        let bytes = summary.map { Int64($0.fileSizeBytes) } ?? fileSize(at: url)
        let record = CaptureRecord(id: id, kind: .gif, createdAt: Date(),
                                   pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                                   fileSizeBytes: bytes, savedPath: url.path,
                                   hasLibraryAsset: false,
                                   durationSeconds: summary?.durationSecs,
                                   frameCount: summary.map { Int($0.frameCount) })
        do {
            if let first = ThumbnailMaker.firstFrame(ofImageAt: url) {
                try writeThumbnail(of: first, id: id)
            }
            try commit([record] + records)
        } catch {
            removeFiles(for: id)
            throw error
        }
        return record
    }

    func markSaved(id: UUID, to url: URL, annotated: CGImage?) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.recordNotFound }
        var updated = records
        updated[index].savedPath = url.path
        updated[index].fileSizeBytes = fileSize(at: url)
        if let annotated {
            try ensureDirectories()
            try writeThumbnail(of: annotated, id: id)
        }
        try commit(updated)
    }

    func delete(id: UUID) throws {
        try commit(records.filter { $0.id != id })
        removeFiles(for: id)
    }

    /// Removes records older than `days` (0 = keep forever) and their library
    /// files, and sweeps assets or thumbnails that belong to no record.
    func prune(olderThan days: Int, now: Date = Date()) throws {
        sweepOrphanedFiles()
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let stale = records.filter { $0.createdAt < cutoff }
        guard !stale.isEmpty else { return }
        try commit(records.filter { $0.createdAt >= cutoff })
        for record in stale { removeFiles(for: record.id) }
    }

    func image(for id: UUID) -> CGImage? {
        let url = assetURL(for: id)
        guard fm.fileExists(atPath: url.path) else { return nil }
        return ThumbnailMaker.firstFrame(ofImageAt: url)
    }

    // MARK: Persistence

    private func ensureDirectories() throws {
        try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbsURL, withIntermediateDirectories: true)
    }

    private func writeThumbnail(of image: CGImage, id: UUID) throws {
        guard let thumb = ThumbnailMaker.thumbnail(from: image), let jpeg = ThumbnailMaker.jpegData(thumb) else {
            throw LibraryError.encodeFailed
        }
        try jpeg.write(to: thumbnailURL(for: id), options: .atomic)
    }

    private func fileSize(at url: URL) -> Int64 {
        ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func removeFiles(for id: UUID) {
        try? fm.removeItem(at: assetURL(for: id))
        try? fm.removeItem(at: thumbnailURL(for: id))
    }

    /// Deletes files in assets/ and thumbs/ whose name is not a known record id.
    private func sweepOrphanedFiles() {
        let known = Set(records.map { $0.id.uuidString })
        for dir in [assetsURL, thumbsURL] {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                let stem = (name as NSString).deletingPathExtension
                if !known.contains(stem) {
                    try? fm.removeItem(at: dir.appendingPathComponent(name))
                }
            }
        }
    }

    /// Persists `new` and only then publishes it, so memory never disagrees with disk.
    private func commit(_ new: [CaptureRecord]) throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(new)
        try data.write(to: indexURL, options: .atomic)
        records = new
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// Decodes one record, yielding nil instead of failing the whole array.
    private struct FailableRecord: Decodable {
        let record: CaptureRecord?
        init(from decoder: Decoder) {
            record = try? CaptureRecord(from: decoder)
        }
    }

    /// A missing index is an empty library. An index that exists but cannot be
    /// read, cannot be decoded, or decodes to no usable record is moved aside
    /// (never overwritten); individually bad records are skipped.
    private static func load(from url: URL) -> [CaptureRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            moveAside(url, reason: "unreadable: \(error.localizedDescription)")
            return []
        }
        do {
            let entries = try JSONDecoder().decode([FailableRecord].self, from: data)
            let decoded = entries.compactMap(\.record)
            if !entries.isEmpty && decoded.isEmpty {
                moveAside(url, reason: "none of \(entries.count) records could be decoded")
                return []
            }
            return decoded
        } catch {
            moveAside(url, reason: "undecodable: \(error.localizedDescription)")
            return []
        }
    }

    private static func moveAside(_ url: URL, reason: String) {
        NSLog("CaptureLibrary: index.json %@; moving it aside", reason)
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("index.json.corrupt-\(Int(Date().timeIntervalSince1970 * 1000))")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            NSLog("CaptureLibrary: could not move the corrupt index aside: %@", error.localizedDescription)
        }
    }
}
