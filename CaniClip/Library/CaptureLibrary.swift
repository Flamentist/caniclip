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
    func addScreenshot(_ image: CGImage) throws -> CaptureRecord {
        try ensureDirectories()
        let id = UUID()
        let png = try ImageExporter.pngData(from: image)
        try png.write(to: assetURL(for: id), options: .atomic)
        try writeThumbnail(of: image, id: id)
        let record = CaptureRecord(id: id, kind: .screenshot, createdAt: Date(),
                                   pixelWidth: image.width, pixelHeight: image.height,
                                   fileSizeBytes: Int64(png.count), savedPath: nil,
                                   hasLibraryAsset: true, durationSeconds: nil, frameCount: nil)
        records.insert(record, at: 0)
        try save()
        return record
    }

    @discardableResult
    func addGif(url: URL, summary: GifSummary?) throws -> CaptureRecord {
        try ensureDirectories()
        let id = UUID()
        let size = ThumbnailMaker.pixelSize(ofImageAt: url) ?? .zero
        if let first = ThumbnailMaker.firstFrame(ofImageAt: url) {
            try writeThumbnail(of: first, id: id)
        }
        let bytes = summary.map { Int64($0.fileSizeBytes) } ?? fileSize(at: url)
        let record = CaptureRecord(id: id, kind: .gif, createdAt: Date(),
                                   pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                                   fileSizeBytes: bytes, savedPath: url.path,
                                   hasLibraryAsset: false,
                                   durationSeconds: summary?.durationSecs,
                                   frameCount: summary.map { Int($0.frameCount) })
        records.insert(record, at: 0)
        try save()
        return record
    }

    func markSaved(id: UUID, to url: URL, annotated: CGImage?) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.recordNotFound }
        records[index].savedPath = url.path
        records[index].fileSizeBytes = fileSize(at: url)
        if let annotated {
            try ensureDirectories()
            try writeThumbnail(of: annotated, id: id)
        }
        try save()
    }

    func delete(id: UUID) throws {
        try? fm.removeItem(at: assetURL(for: id))
        try? fm.removeItem(at: thumbnailURL(for: id))
        records.removeAll { $0.id == id }
        try save()
    }

    /// Removes records older than `days` (0 = keep forever) and their library files.
    func prune(olderThan days: Int, now: Date = Date()) throws {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let stale = records.filter { $0.createdAt < cutoff }
        guard !stale.isEmpty else { return }
        for record in stale {
            try? fm.removeItem(at: assetURL(for: record.id))
            try? fm.removeItem(at: thumbnailURL(for: record.id))
        }
        records.removeAll { $0.createdAt < cutoff }
        try save()
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

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private func save() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func load(from url: URL) -> [CaptureRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        return (try? d.decode([CaptureRecord].self, from: data)) ?? []
    }
}
