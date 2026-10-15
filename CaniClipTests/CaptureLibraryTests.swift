import XCTest
@testable import CaniClip

@MainActor
final class CaptureLibraryTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-lib-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func red(_ w: Int = 40, _ h: Int = 20) -> CGImage {
        TestImages.solid(width: w, height: h, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    }

    /// A real 2-frame GIF written by the Rust encoder.
    private func makeGif() throws -> (URL, GifSummary) {
        let encoder = try GifEncoder(settings: GifSettings(maxWidth: nil, maxHeight: nil, quality: 80, fast: true, repeat: 0))
        var bytes = [UInt8](repeating: 0, count: 12 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes[i] = 200; bytes[i + 3] = 255 }
        try encoder.addFrame(pixels: Data(bytes), width: 12, height: 8, format: .rgba, timestampSecs: 0)
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes[i] = 20; bytes[i + 2] = 200 }
        try encoder.addFrame(pixels: Data(bytes), width: 12, height: 8, format: .rgba, timestampSecs: 0.2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-lib-\(UUID().uuidString).gif")
        let summary = try encoder.finish(outputPath: url.path, endTimestampSecs: nil)
        return (url, summary)
    }

    func testAddScreenshotWritesAssetThumbnailAndIndex() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red())
        XCTAssertEqual(rec.kind, .screenshot)
        XCTAssertEqual(rec.pixelWidth, 40)
        XCTAssertEqual(rec.pixelHeight, 20)
        XCTAssertTrue(rec.hasLibraryAsset)
        XCTAssertNil(rec.savedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.assetURL(for: rec.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.thumbnailURL(for: rec.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
        XCTAssertGreaterThan(rec.fileSizeBytes, 0)
        XCTAssertEqual(lib.bestFileURL(for: rec), lib.assetURL(for: rec.id))
    }

    func testRecordsAreNewestFirstAndPersistAcrossInstances() throws {
        let lib = CaptureLibrary(rootURL: root)
        let first = try lib.addScreenshot(red())
        let second = try lib.addScreenshot(red(10, 10))
        XCTAssertEqual(lib.records.map(\.id), [second.id, first.id])
        let reloaded = CaptureLibrary(rootURL: root)
        XCTAssertEqual(reloaded.records, lib.records)
    }

    func testAddGifStoresThumbnailOnlyAndPointsAtTheFile() throws {
        let lib = CaptureLibrary(rootURL: root)
        let (url, summary) = try makeGif()
        defer { try? FileManager.default.removeItem(at: url) }
        let rec = try lib.addGif(url: url, summary: summary)
        XCTAssertEqual(rec.kind, .gif)
        XCTAssertEqual(rec.savedPath, url.path)
        XCTAssertFalse(rec.hasLibraryAsset)
        XCTAssertEqual(rec.pixelWidth, 12)
        XCTAssertEqual(rec.pixelHeight, 8)
        XCTAssertEqual(rec.frameCount, Int(summary.frameCount))
        XCTAssertEqual(rec.durationSeconds ?? -1, summary.durationSecs, accuracy: 1e-9)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.assetURL(for: rec.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.thumbnailURL(for: rec.id).path))
        XCTAssertEqual(lib.bestFileURL(for: rec), url)
    }

    func testMarkSavedUpdatesPathSizeAndThumbnail() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red())
        let thumbBefore = try Data(contentsOf: lib.thumbnailURL(for: rec.id))
        let saved = root.appendingPathComponent("saved.png")
        let annotated = TestImages.solid(width: 40, height: 20, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        try ImageExporter.writePNG(annotated, to: saved)
        try lib.markSaved(id: rec.id, to: saved, annotated: annotated)
        let updated = lib.records[0]
        XCTAssertEqual(updated.savedPath, saved.path)
        XCTAssertEqual(updated.fileSizeBytes, Int64((try FileManager.default.attributesOfItem(atPath: saved.path))[.size] as! UInt64))
        XCTAssertNotEqual(try Data(contentsOf: lib.thumbnailURL(for: rec.id)), thumbBefore)
        XCTAssertEqual(lib.bestFileURL(for: updated), saved)
    }

    func testDeleteRemovesRecordAndLibraryFilesOnly() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red())
        let saved = root.appendingPathComponent("kept.png")
        try ImageExporter.writePNG(red(), to: saved)
        try lib.markSaved(id: rec.id, to: saved, annotated: nil)
        try lib.delete(id: rec.id)
        XCTAssertTrue(lib.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.assetURL(for: rec.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.thumbnailURL(for: rec.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "user's file must survive")
    }

    func testPruneNeverTouchesSavedFile() throws {
        let lib = CaptureLibrary(rootURL: root)
        let old = try lib.addScreenshot(red())
        let saved = root.appendingPathComponent("old.png")
        try ImageExporter.writePNG(red(), to: saved)
        try lib.markSaved(id: old.id, to: saved, annotated: nil)
        let fresh = try lib.addScreenshot(red(8, 8))
        let now = old.createdAt.addingTimeInterval(31 * 86_400)
        // Make `fresh` look recent relative to `now` by pruning with a 30-day window:
        // old is 31 days before now, fresh was created a moment after old, so both
        // would be pruned — test the boundary by using a 40-day window first.
        try lib.prune(olderThan: 40, now: now)
        XCTAssertEqual(lib.records.count, 2)
        try lib.prune(olderThan: 30, now: now)
        XCTAssertEqual(lib.records.map(\.id), [], "both records are older than 30 days relative to now")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "pruning must not delete the saved file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.assetURL(for: old.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.assetURL(for: fresh.id).path))
    }

    func testPruneZeroKeepsForever() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red())
        try lib.prune(olderThan: 0, now: rec.createdAt.addingTimeInterval(365 * 86_400))
        XCTAssertEqual(lib.records.count, 1)
    }

    func testBestFileURLIsNilWhenEverythingIsGone() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red())
        try FileManager.default.removeItem(at: lib.assetURL(for: rec.id))
        var ghost = rec
        ghost.savedPath = root.appendingPathComponent("nope.png").path
        XCTAssertNil(lib.bestFileURL(for: ghost))
        XCTAssertNil(lib.image(for: rec.id))
    }

    func testImageForIDLoadsTheAsset() throws {
        let lib = CaptureLibrary(rootURL: root)
        let rec = try lib.addScreenshot(red(30, 12))
        let img = lib.image(for: rec.id)
        XCTAssertEqual(img?.width, 30)
        XCTAssertEqual(img?.height, 12)
    }

    func testThumbnailFitsLongSide() {
        let big = TestImages.solid(width: 1920, height: 1080, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        let thumb = ThumbnailMaker.thumbnail(from: big, longSide: 480)!
        XCTAssertEqual(thumb.width, 480)
        XCTAssertEqual(thumb.height, 270)
        let small = ThumbnailMaker.thumbnail(from: TestImages.solid(width: 100, height: 50, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)), longSide: 480)!
        XCTAssertEqual(small.width, 100, "images smaller than the long side are not upscaled")
        let jpeg = ThumbnailMaker.jpegData(thumb)!
        XCTAssertEqual([UInt8](jpeg.prefix(2)), [0xFF, 0xD8])
    }
}
