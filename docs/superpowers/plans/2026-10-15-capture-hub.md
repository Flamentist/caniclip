# CaniClip Capture Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CaniClip a main window with large capture tiles and a browsable, app-managed history of every screenshot and GIF.

**Architecture:** A `CaptureLibrary` store under Application Support keeps an index, screenshot assets and thumbnails; the coordinator records every capture into it and the editor reports saves back. A `HubWindowController` hosts a SwiftUI `HubView` driven by a testable `HubViewModel`; opening the hub switches the app to a regular activation policy (Dock icon, File menu) and closing it returns to accessory mode. The hub hides itself while a capture is in progress.

**Tech Stack:** Swift 6.2 compiler in Swift 5 mode, AppKit + SwiftUI, ImageIO for thumbnails, existing Rust core via UniFFI (unchanged), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-15-capture-hub-design.md` (builds on `2026-10-15-caniclip-design.md`)

## Global Constraints

- Library root: `~/Library/Application Support/CaniClip/Library/` with `index.json`, `assets/<id>.png`, `thumbs/<id>.jpg`; thumbnails long side 480 px, JPEG quality 0.8.
- Screenshots are copied into the library at capture time; GIFs are never duplicated (thumbnail only).
- Library failures are non-fatal: capture delivery proceeds exactly as before.
- Retention preference `historyRetentionDays` accepts only 0 (forever), 7, 30, 90; default 30. `openHubAtLaunch` defaults to false. First launch opens the hub once.
- Deleting from the hub never touches files in the user's save folder.
- Hub window default 900×600, minimum 640×420, autosaved frame name `CaniClipHub`.
- `LSUIElement` stays true; the activation policy is `.regular` only while a hub window is open.
- Every task re-runs `xcodegen generate` after adding files and runs the Swift suite with `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh` (created in Task 1) and the Rust suite is untouched.
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Deviations from the spec (decided while planning)

- Spec §3.1 puts Settings and "Open Save Folder" in an NSToolbar. The plan puts them as buttons in the hub's header row instead: SwiftUI `.toolbar` items inside an `NSHostingView` do not reliably attach to an AppKit window, and a header row needs no bridging code.
- Spec §3.1 keyboard handling (Delete removes the selection, Return opens) is left to a follow-up; the cards' hover strip and context menu cover every action.

## Review Focus

1. A record whose asset or saved file was deleted outside the app must show as missing with Open and Reveal disabled while Delete still works, never crash on load. Pinned in Task 1 (`bestFileURL` returns nil when both files are gone) and Task 4 (view model `isMissing`).
2. Pruning old history must never delete the user's saved file, only the library copy and thumbnail. Pinned in Task 1 (`testPruneNeverTouchesSavedFile`).
3. An unwritable library root must not stop screenshots from being delivered. Pinned in Task 3 (`testLibraryFailureDoesNotBlockDelivery`).
4. The hub must come back after a cancelled selection, not only after a successful capture. Pinned in Task 5 (`HubVisibilityReducer` test for selecting→idle).
5. Closing the last hub window returns the app to accessory mode; closing one of two does not. Pinned in Task 5 (`ActivationPolicyRule` test).

---

### Task 1: Capture library model, thumbnails and store

**Files:**
- Create: `CaniClip/Library/CaptureRecord.swift`
- Create: `CaniClip/Library/ThumbnailMaker.swift`
- Create: `CaniClip/Library/CaptureLibrary.swift`
- Create: `CaniClipTests/CaptureLibraryTests.swift`
- Create: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh` (test runner; gitignored)

**Interfaces:**
- Produces: `enum CaptureKindRecord: String, Codable { screenshot, gif }`; `struct CaptureRecord: Identifiable, Codable, Equatable { id: UUID; kind; createdAt: Date; pixelWidth: Int; pixelHeight: Int; fileSizeBytes: Int64; savedPath: String?; hasLibraryAsset: Bool; durationSeconds: Double?; frameCount: Int? }`.
- Produces: `enum ThumbnailMaker { static func thumbnail(from: CGImage, longSide: Int = 480) -> CGImage?; static func jpegData(_: CGImage, quality: CGFloat = 0.8) -> Data?; static func firstFrame(ofImageAt: URL) -> CGImage?; static func pixelSize(ofImageAt: URL) -> CGSize? }`.
- Produces: `@MainActor final class CaptureLibrary: ObservableObject { static let shared; static var defaultRoot: URL; init(rootURL: URL); @Published private(set) var records: [CaptureRecord]; func assetURL(for id: UUID) -> URL; func thumbnailURL(for id: UUID) -> URL; func bestFileURL(for record: CaptureRecord) -> URL?; @discardableResult func addScreenshot(_ image: CGImage) throws -> CaptureRecord; @discardableResult func addGif(url: URL, summary: GifSummary?) throws -> CaptureRecord; func markSaved(id: UUID, to url: URL, annotated: CGImage?) throws; func delete(id: UUID) throws; func prune(olderThan days: Int, now: Date = Date()) throws; func image(for id: UUID) -> CGImage? }`.

- [ ] **Step 1: Create the test runner script**

```bash
mkdir -p .superpowers/sdd/2026-10-15-capture-hub && cat > .superpowers/sdd/2026-10-15-capture-hub/xctest.sh <<'SH'
#!/bin/bash
cd "$(dirname "$0")/../../.."
xcodebuild test -project CaniClip.xcodeproj -scheme CaniClip -destination 'platform=macOS,arch=arm64' > .superpowers/sdd/2026-10-15-capture-hub/xctest-last.log 2>&1
status=$?
grep -E "error:|failed -|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" .superpowers/sdd/2026-10-15-capture-hub/xctest-last.log | tail -4
exit $status
SH
chmod +x .superpowers/sdd/2026-10-15-capture-hub/xctest.sh
```

- [ ] **Step 2: Write the failing tests**

`CaniClipTests/CaptureLibraryTests.swift`:
```swift
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
```

- [ ] **Step 3: Run to verify compile failure**

Run: `xcodegen generate -q; .superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | head -3`
Expected: `cannot find 'CaptureLibrary' in scope`.

- [ ] **Step 4: Implement the model and thumbnail helper**

`CaniClip/Library/CaptureRecord.swift`:
```swift
import Foundation

enum CaptureKindRecord: String, Codable {
    case screenshot, gif
}

/// One entry in the capture history. Files it refers to live either in the
/// user's save folder (`savedPath`) or in the library's `assets/` directory.
struct CaptureRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: CaptureKindRecord
    let createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSizeBytes: Int64
    var savedPath: String?
    var hasLibraryAsset: Bool
    var durationSeconds: Double?
    var frameCount: Int?
}
```

`CaniClip/Library/ThumbnailMaker.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailMaker {
    /// Downscales so the longer side is `longSide` pixels; never upscales.
    static func thumbnail(from image: CGImage, longSide: Int = 480) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1.0, Double(longSide) / Double(max(w, h)))
        let tw = max(1, Int((Double(w) * scale).rounded()))
        let th = max(1, Int((Double(h) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    static func jpegData(_ image: CGImage, quality: CGFloat = 0.8) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func firstFrame(ofImageAt url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pixelSize(ofImageAt url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}
```

- [ ] **Step 5: Implement the store**

`CaniClip/Library/CaptureLibrary.swift`:
```swift
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
        e.dateEncodingStrategy = .iso8601
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
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([CaptureRecord].self, from: data)) ?? []
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `xcodegen generate -q; .superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` with 82 tests (72 + 10).

- [ ] **Step 7: Commit**

```bash
git add CaniClip/Library CaniClipTests/CaptureLibraryTests.swift
git commit -m "feat(library): capture history store with thumbnails and retention

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: History preferences and Settings controls

**Files:**
- Modify: `CaniClip/Settings/Preferences.swift`
- Modify: `CaniClip/Settings/SettingsView.swift` (General tab)
- Modify: `CaniClipTests/PreferencesTests.swift`

**Interfaces:**
- Produces: `Preferences.historyRetentionDays: Int` (default 30; `normalized()` maps anything outside {0, 7, 30, 90} to 30) and `Preferences.openHubAtLaunch: Bool` (default false). `static let retentionOptions: [(days: Int, title: String)]`.

- [ ] **Step 1: Add the failing tests**

Append inside the class in `CaniClipTests/PreferencesTests.swift`:
```swift
    func testHistoryDefaultsAndNormalisation() {
        let p = Preferences()
        XCTAssertEqual(p.historyRetentionDays, 30)
        XCTAssertFalse(p.openHubAtLaunch)
        var bad = Preferences()
        bad.historyRetentionDays = 12
        XCTAssertEqual(bad.normalized().historyRetentionDays, 30)
        bad.historyRetentionDays = 0
        XCTAssertEqual(bad.normalized().historyRetentionDays, 0)
        bad.historyRetentionDays = 90
        XCTAssertEqual(bad.normalized().historyRetentionDays, 90)
    }

    func testHistoryKeysDecodeWithDefaultsWhenMissing() throws {
        let json = #"{"gifFPS": 30}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(p.historyRetentionDays, 30)
        XCTAssertFalse(p.openHubAtLaunch)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | head -2`
Expected: `value of type 'Preferences' has no member 'historyRetentionDays'`.

- [ ] **Step 3: Implement the preferences**

In `CaniClip/Settings/Preferences.swift`, after `var maxRecordingSeconds: Int = 60` add:
```swift
    var historyRetentionDays: Int = 30
    var openHubAtLaunch: Bool = false

    static let retentionOptions: [(days: Int, title: String)] = [
        (7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Forever"),
    ]
```
In `init(from:)`, after the `maxRecordingSeconds` line add:
```swift
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? d.historyRetentionDays
        openHubAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .openHubAtLaunch) ?? d.openHubAtLaunch
```
In `normalized()`, before `return p` add:
```swift
        if !Preferences.retentionOptions.contains(where: { $0.days == p.historyRetentionDays }) {
            p.historyRetentionDays = 30
        }
```

- [ ] **Step 4: Add the Settings controls**

In `CaniClip/Settings/SettingsView.swift`, inside the General `Form`, directly after the `Picker("After screenshot", …) { … }` block add:
```swift
            Picker("Keep history", selection: $store.preferences.historyRetentionDays) {
                ForEach(Preferences.retentionOptions, id: \.days) { Text($0.title).tag($0.days) }
            }
            Toggle("Open window at launch", isOn: $store.preferences.openHubAtLaunch)
```

- [ ] **Step 5: Run the tests**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2`
Expected: `** TEST SUCCEEDED **`, 84 tests.

- [ ] **Step 6: Commit**

```bash
git add CaniClip/Settings CaniClipTests/PreferencesTests.swift
git commit -m "feat(settings): history retention and open-at-launch preferences

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Record every capture in the library

**Files:**
- Modify: `CaniClip/Editor/EditorWindowController.swift` (add `onSaved`, call it from `save()` and `saveAs()`)
- Modify: `CaniClip/App/CaptureCoordinator.swift`
- Modify: `CaniClipTests/CaptureCoordinatorTests.swift`

**Interfaces:**
- Produces: `EditorWindowController.onSaved: ((URL, CGImage) -> Void)?` invoked after every successful save with the written URL and the rasterised image.
- Produces in `CaptureCoordinator`: `init(appState:preferences:statusItem:library: CaptureLibrary = .shared)`, `let library: CaptureLibrary`, `func openEditor(_ image: CGImage, recordID: UUID? = nil)`. Library failures present one alert titled "History is unavailable" per app run and never block delivery.

- [ ] **Step 1: Write the failing tests**

In `CaniClipTests/CaptureCoordinatorTests.swift` replace `makeCoordinator(saveFolder:)` with:
```swift
    private var libraryRoot: URL!

    private func makeCoordinator(saveFolder: String, afterCapture: AfterCaptureAction = .saveToFolder,
                                 libraryRoot: URL? = nil) -> CaptureCoordinator {
        let defaults = UserDefaults(suiteName: "caniclip.tests.coordinator.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        store.preferences.saveFolderPath = saveFolder
        store.preferences.afterCapture = afterCapture
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: {}, captureFullScreen: {}, recordArea: {}, openSettings: {}, quit: {}))
        self.libraryRoot = libraryRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-coord-lib-\(UUID().uuidString)")
        let library = CaptureLibrary(rootURL: self.libraryRoot)
        return CaptureCoordinator(appState: AppState(), preferences: store, statusItem: status, library: library)
    }
```
and append these tests inside the class:
```swift
    func testClipboardOnlyScreenshotIsRecordedWithALibraryCopy() {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .copyToClipboard)
        let image = TestImages.solid(width: 10, height: 6, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        coordinator.deliverScreenshot(image)
        XCTAssertEqual(coordinator.library.records.count, 1)
        let record = coordinator.library.records[0]
        XCTAssertTrue(record.hasLibraryAsset)
        XCTAssertNil(record.savedPath)
        XCTAssertEqual(coordinator.appState.mode, .idle)
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func testEditorSaveUpdatesTheRecord() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: libraryRoot) }
        let coordinator = makeCoordinator(saveFolder: folder.path, afterCapture: .openEditor)
        let image = TestImages.solid(width: 10, height: 6, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        coordinator.deliverScreenshot(image)
        let editor = coordinator.editorsForTesting[0]
        editor.editorDocument.add(Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 3, height: 3))))
        let url = try editor.save()
        XCTAssertEqual(coordinator.library.records[0].savedPath, url.path)
        coordinator.closeAllEditorsForTesting()
    }

    func testLibraryFailureDoesNotBlockDelivery() throws {
        // A regular file where the library root should be makes every write fail.
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-blocked-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .copyToClipboard, libraryRoot: blocked)
        let image = TestImages.solid(width: 10, height: 6, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        coordinator.deliverScreenshot(image)
        coordinator.deliverScreenshot(image)
        XCTAssertEqual(coordinator.appState.mode, .idle)
        XCTAssertEqual(presented.count, 1, "history failure is reported once per run")
        XCTAssertEqual(presented[0].0, "History is unavailable")
        XCTAssertTrue(coordinator.library.records.isEmpty)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | head -2`
Expected: `extra argument 'library' in call`.

- [ ] **Step 3: Report saves from the editor**

In `CaniClip/Editor/EditorWindowController.swift`:
- after `var onClose: (() -> Void)?` add
```swift
    /// Reports every successful save (URL and rasterised image) so history can follow it.
    var onSaved: ((URL, CGImage) -> Void)?
```
- in `save()`, after `editorDocument.markSaved(to: url)` add `onSaved?(url, image)`.
- in `saveAs()`, after `self.editorDocument.markSaved(to: url)` add `self.onSaved?(url, image)`.

- [ ] **Step 4: Record captures in the coordinator**

In `CaniClip/App/CaptureCoordinator.swift`:

Replace the stored properties block from `let statusItem: StatusItemController` through `let capturer = ScreenCapturer()` with:
```swift
    let statusItem: StatusItemController
    let library: CaptureLibrary
    let overlay = SelectionOverlayController()
    let capturer = ScreenCapturer()
    private var reportedLibraryFailure = false
```
Replace `init`:
```swift
    init(appState: AppState, preferences: PreferencesStore, statusItem: StatusItemController,
         library: CaptureLibrary = .shared) {
        self.appState = appState
        self.preferences = preferences
        self.statusItem = statusItem
        self.library = library
        do {
            try library.prune(olderThan: preferences.preferences.historyRetentionDays)
        } catch {
            reportLibraryFailure(error)
        }
    }
```
Replace `deliverScreenshot(_:)`:
```swift
    func deliverScreenshot(_ image: CGImage) {
        let recordID = recordScreenshot(image)
        switch preferences.preferences.afterCapture {
        case .openEditor:
            openEditor(image, recordID: recordID)
        case .copyToClipboard:
            ImageExporter.copyToClipboard(image)
            playCaptureSound()
            appState.transition(to: .idle)
        case .saveToFolder:
            do {
                let url = try saveScreenshot(image)
                if let recordID { try? library.markSaved(id: recordID, to: url, annotated: nil) }
                playCaptureSound()
                appState.transition(to: .idle)
            } catch {
                // Never drop the capture: explain, then hand it to the editor,
                // whose Save As… lets the user pick a writable location.
                ErrorPresenter.present(error, title: "Could not save screenshot")
                openEditor(image, recordID: recordID)
            }
        }
    }

    // MARK: History

    private func recordScreenshot(_ image: CGImage) -> UUID? {
        do {
            return try library.addScreenshot(image).id
        } catch {
            reportLibraryFailure(error)
            return nil
        }
    }

    private func recordGif(url: URL, summary: GifSummary?) {
        do {
            try library.addGif(url: url, summary: summary)
        } catch {
            reportLibraryFailure(error)
        }
    }

    /// History is a convenience; its failures are shown once and never block a capture.
    private func reportLibraryFailure(_ error: Error) {
        NSLog("CaptureLibrary error: %@", error.localizedDescription)
        guard !reportedLibraryFailure else { return }
        reportedLibraryFailure = true
        ErrorPresenter.present(error, title: "History is unavailable")
    }
```
Replace the signature and first lines of `openEditor`:
```swift
    func openEditor(_ image: CGImage, recordID: UUID? = nil) {
        let controller = EditorWindowController(image: image, preferences: preferences)
        controller.onSaved = { [weak self] url, annotated in
            guard let self, let recordID else { return }
            do { try self.library.markSaved(id: recordID, to: url, annotated: annotated) } catch { self.reportLibraryFailure(error) }
        }
```
(the rest of the method is unchanged).

In `recordingFinished(_:)`: in the `.success` branch add `recordGif(url: output.url, summary: output.summary)` before `presentRecordingResult(output)`; in the `OutputUnwritable` branch add `recordGif(url: kept, summary: nil)` after `let kept = …`.

- [ ] **Step 5: Run the tests**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2`
Expected: `** TEST SUCCEEDED **`, 87 tests. Then `grep -rn "StatusMenuActions(" CaniClipTests CaniClip | wc -l` to confirm no other call sites need updating (expected 3: AppDelegate and two tests).

- [ ] **Step 6: Commit**

```bash
git add CaniClip CaniClipTests
git commit -m "feat(library): record screenshots, saves and recordings in the history

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Hub view model

**Files:**
- Create: `CaniClip/Hub/HubViewModel.swift`
- Create: `CaniClipTests/HubViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class HubViewModel: ObservableObject { enum Filter: String, CaseIterable, Identifiable { all, screenshots, gifs }; @Published var filter; @Published var selection: UUID?; let library: CaptureLibrary; init(library:); var visibleRecords: [CaptureRecord]; struct Section: Identifiable { title: String; records: [CaptureRecord] }; func sections(now: Date = Date(), calendar: Calendar = .current) -> [Section]; func isMissing(_: CaptureRecord) -> Bool; static func sectionTitle(for: Date, now: Date, calendar: Calendar) -> String; static func relativeTime(_: Date, now: Date, locale: Locale = .current) -> String; static func sizeText(bytes: Int64) -> String; static func dimensionsText(_: CaptureRecord) -> String }`.

- [ ] **Step 1: Write the failing tests**

`CaniClipTests/HubViewModelTests.swift`:
```swift
import XCTest
@testable import CaniClip

@MainActor
final class HubViewModelTests: XCTestCase {
    private var root: URL!
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_792_000_323) // 2026-10-14 17:52:03 UTC

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-hub-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testFilterSelectsByKind() throws {
        let lib = CaptureLibrary(rootURL: root)
        let shot = try lib.addScreenshot(TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let gifURL = root.appendingPathComponent("x.gif")
        try Data([0x47, 0x49, 0x46]).write(to: gifURL)   // not a real gif; size falls back to 0, thumbnail skipped
        let gif = try lib.addGif(url: gifURL, summary: nil)
        let vm = HubViewModel(library: lib)
        XCTAssertEqual(vm.visibleRecords.map(\.id), [gif.id, shot.id])
        vm.filter = .screenshots
        XCTAssertEqual(vm.visibleRecords.map(\.id), [shot.id])
        vm.filter = .gifs
        XCTAssertEqual(vm.visibleRecords.map(\.id), [gif.id])
    }

    func testSectionTitles() {
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-3600), now: now, calendar: utc), "Today")
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-86_400), now: now, calendar: utc), "Yesterday")
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-3 * 86_400), now: now, calendar: utc), "This Week")
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-20 * 86_400), now: now, calendar: utc), "Earlier")
    }

    func testRelativeTime() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(HubViewModel.relativeTime(now.addingTimeInterval(-30), now: now, locale: en), "Just now")
        XCTAssertEqual(HubViewModel.relativeTime(now.addingTimeInterval(-120), now: now, locale: en), "2 minutes ago")
        XCTAssertEqual(HubViewModel.relativeTime(now.addingTimeInterval(-2 * 86_400), now: now, locale: en), "2 days ago")
    }

    func testIsMissingWhenFilesAreGone() throws {
        let lib = CaptureLibrary(rootURL: root)
        let shot = try lib.addScreenshot(TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let vm = HubViewModel(library: lib)
        XCTAssertFalse(vm.isMissing(shot))
        try FileManager.default.removeItem(at: lib.assetURL(for: shot.id))
        XCTAssertTrue(vm.isMissing(shot))
    }

    func testTextHelpers() {
        let rec = CaptureRecord(id: UUID(), kind: .screenshot, createdAt: now, pixelWidth: 1200, pixelHeight: 800,
                                fileSizeBytes: 2_048_000, savedPath: nil, hasLibraryAsset: true, durationSeconds: nil, frameCount: nil)
        XCTAssertEqual(HubViewModel.dimensionsText(rec), "1200 × 800")
        XCTAssertTrue(HubViewModel.sizeText(bytes: rec.fileSizeBytes).contains("MB"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate -q; .superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | head -2`
Expected: `cannot find 'HubViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

`CaniClip/Hub/HubViewModel.swift`:
```swift
import Combine
import Foundation

@MainActor
final class HubViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", screenshots = "Screenshots", gifs = "GIFs"
        var id: String { rawValue }
    }

    struct Section: Identifiable {
        let title: String
        let records: [CaptureRecord]
        var id: String { title }
    }

    @Published var filter: Filter = .all
    @Published var selection: UUID?
    let library: CaptureLibrary
    private var cancellables: Set<AnyCancellable> = []

    init(library: CaptureLibrary) {
        self.library = library
        library.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var visibleRecords: [CaptureRecord] {
        switch filter {
        case .all: return library.records
        case .screenshots: return library.records.filter { $0.kind == .screenshot }
        case .gifs: return library.records.filter { $0.kind == .gif }
        }
    }

    func sections(now: Date = Date(), calendar: Calendar = .current) -> [Section] {
        var order: [String] = []
        var buckets: [String: [CaptureRecord]] = [:]
        for record in visibleRecords {
            let title = Self.sectionTitle(for: record.createdAt, now: now, calendar: calendar)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(record)
        }
        return order.map { Section(title: $0, records: buckets[$0] ?? []) }
    }

    func isMissing(_ record: CaptureRecord) -> Bool {
        library.bestFileURL(for: record) == nil
    }

    static func sectionTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo { return "This Week" }
        return "Earlier"
    }

    static func relativeTime(_ date: Date, now: Date, locale: Locale = .current) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    static func sizeText(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func dimensionsText(_ record: CaptureRecord) -> String {
        "\(record.pixelWidth) × \(record.pixelHeight)"
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2`
Expected: `** TEST SUCCEEDED **`, 92 tests. If `testFilterSelectsByKind` fails inside `addGif` because the fake GIF has no first frame, that is expected to be tolerated: `addGif` skips the thumbnail when `firstFrame` returns nil (see Task 1).

- [ ] **Step 5: Commit**

```bash
git add CaniClip/Hub CaniClipTests/HubViewModelTests.swift
git commit -m "feat(hub): view model with filtering, sections and relative times

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Hub window, Dock policy, menus and capture hiding

**Files:**
- Create: `CaniClip/Hub/ActivationPolicyRule.swift`
- Create: `CaniClip/Hub/HubVisibilityReducer.swift`
- Create: `CaniClip/Hub/HubActions.swift`
- Create: `CaniClip/Hub/ActionTile.swift`
- Create: `CaniClip/Hub/CaptureCard.swift`
- Create: `CaniClip/Hub/HubView.swift`
- Create: `CaniClip/Hub/HubWindowController.swift`
- Modify: `CaniClip/App/MainMenu.swift`
- Modify: `CaniClip/App/StatusItemController.swift` (add `openHub` action and menu item)
- Modify: `CaniClip/App/CaptureCoordinator.swift` (hub, actions, visibility, policy)
- Modify: `CaniClip/App/AppDelegate.swift` (menu actions, first launch, reopen)
- Modify: `CaniClipTests/CaptureCoordinatorTests.swift` (`StatusMenuActions` gains `openHub`)
- Create: `CaniClipTests/HubRulesTests.swift`

**Interfaces:**
- Produces: `enum ActivationPolicyRule { static func policy(openHubWindows: Int) -> NSApplication.ActivationPolicy }`.
- Produces: `struct HubVisibilityReducer { enum Action { hide, restore }; private(set) var hiddenForCapture: Bool; mutating func action(for mode: AppMode, hubVisible: Bool) -> Action? }`.
- Produces: `struct HubActions { captureArea, captureFullScreen, recordArea, openSettings, openSaveFolder: () -> Void; openRecord, copyRecord, revealRecord, deleteRecord: (CaptureRecord) -> Void }`.
- Produces: `@MainActor final class HubWindowController: NSWindowController, NSWindowDelegate { init(viewModel: HubViewModel, actions: HubActions); var onClose: (() -> Void)?; var isShowing: Bool; func present(); func hideForCapture(); func restoreAfterCapture() }`.
- Produces: `StatusMenuActions.openHub: () -> Void` (new first field after `captureArea`… keep order: captureArea, captureFullScreen, recordArea, openHub, openSettings, quit) and a menu item "Open CaniClip" placed after the separator following the three capture items.
- Produces: `final class MenuActions: NSObject` with `@objc` methods and `MainMenu.install(actions: MenuActions)`.
- Produces in `CaptureCoordinator`: `func openHub()`.

- [ ] **Step 1: Write the failing rule tests**

`CaniClipTests/HubRulesTests.swift`:
```swift
import XCTest
@testable import CaniClip

final class HubRulesTests: XCTestCase {
    func testPolicyIsRegularOnlyWhileAHubWindowIsOpen() {
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 0), .accessory)
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 1), .regular)
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 2), .regular)
    }

    func testHubHidesForCaptureAndRestoresEvenWhenCancelled() {
        var r = HubVisibilityReducer()
        XCTAssertEqual(r.action(for: .selecting(.areaScreenshot), hubVisible: true), .hide)
        XCTAssertTrue(r.hiddenForCapture)
        XCTAssertNil(r.action(for: .selecting(.areaScreenshot), hubVisible: false), "already hidden; no second hide")
        XCTAssertEqual(r.action(for: .idle, hubVisible: false), .restore, "cancelled selection restores the hub")
        XCTAssertFalse(r.hiddenForCapture)
    }

    func testHubThatWasNotVisibleIsNeverRestored() {
        var r = HubVisibilityReducer()
        XCTAssertNil(r.action(for: .selecting(.areaRecording), hubVisible: false))
        XCTAssertNil(r.action(for: .recording, hubVisible: false))
        XCTAssertNil(r.action(for: .idle, hubVisible: false))
    }

    func testHubStaysHiddenThroughRecordingAndFinishing() {
        var r = HubVisibilityReducer()
        XCTAssertEqual(r.action(for: .selecting(.areaRecording), hubVisible: true), .hide)
        XCTAssertNil(r.action(for: .recording, hubVisible: false))
        XCTAssertNil(r.action(for: .finishing, hubVisible: false))
        XCTAssertEqual(r.action(for: .idle, hubVisible: false), .restore)
    }

    func testEditingAfterCaptureRestoresTheHub() {
        var r = HubVisibilityReducer()
        _ = r.action(for: .selecting(.areaScreenshot), hubVisible: true)
        XCTAssertEqual(r.action(for: .editing, hubVisible: false), .restore)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate -q; .superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | head -2`
Expected: `cannot find 'ActivationPolicyRule' in scope`.

- [ ] **Step 3: Implement the two rules**

`CaniClip/Hub/ActivationPolicyRule.swift`:
```swift
import AppKit

enum ActivationPolicyRule {
    /// Dock icon and menu bar only while the hub is open; menu-bar-only otherwise.
    static func policy(openHubWindows: Int) -> NSApplication.ActivationPolicy {
        openHubWindows > 0 ? .regular : .accessory
    }
}
```

`CaniClip/Hub/HubVisibilityReducer.swift`:
```swift
import Foundation

/// Decides when the hub window hides for a capture and when it comes back.
/// Pure so the cancelled-selection path can be tested without windows.
struct HubVisibilityReducer {
    enum Action: Equatable { case hide, restore }

    private(set) var hiddenForCapture = false

    mutating func action(for mode: AppMode, hubVisible: Bool) -> Action? {
        switch mode {
        case .selecting, .recording, .finishing:
            guard hubVisible, !hiddenForCapture else { return nil }
            hiddenForCapture = true
            return .hide
        case .idle, .editing:
            guard hiddenForCapture else { return nil }
            hiddenForCapture = false
            return .restore
        }
    }
}
```

- [ ] **Step 4: Run the rule tests**

Run: `.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2`
Expected: `** TEST SUCCEEDED **`, 97 tests.

- [ ] **Step 5: Build the hub views**

`CaniClip/Hub/HubActions.swift`:
```swift
import Foundation

struct HubActions {
    var captureArea: () -> Void
    var captureFullScreen: () -> Void
    var recordArea: () -> Void
    var openSettings: () -> Void
    var openSaveFolder: () -> Void
    var openRecord: (CaptureRecord) -> Void
    var copyRecord: (CaptureRecord) -> Void
    var revealRecord: (CaptureRecord) -> Void
    var deleteRecord: (CaptureRecord) -> Void
}
```

`CaniClip/Hub/ActionTile.swift`:
```swift
import SwiftUI
import KeyboardShortcuts

struct ActionTile: View {
    let title: String
    let symbol: String
    let shortcutName: KeyboardShortcuts.Name
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    private var shortcutText: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? "No shortcut"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title).font(.headline)
                Text(shortcutText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(hovering ? tint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
            )
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
```

`CaniClip/Hub/CaptureCard.swift`:
```swift
import SwiftUI

struct CaptureCard: View {
    let record: CaptureRecord
    let thumbnailURL: URL
    let isMissing: Bool
    let isSelected: Bool
    let relativeTime: String
    let actions: HubActions
    @State private var hovering = false

    private var thumbnail: NSImage? { NSImage(contentsOf: thumbnailURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.secondary.opacity(0.15)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 4) {
                    if isMissing {
                        Label("Missing", systemImage: "exclamationmark.triangle.fill").labelStyle(.iconOnly)
                    }
                    Image(systemName: record.kind == .gif ? "film" : "camera")
                }
                .font(.caption.weight(.semibold))
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .padding(8)

                if hovering {
                    actionStrip
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            Text(relativeTime).font(.subheadline)
            Text("\(HubViewModel.dimensionsText(record)) · \(HubViewModel.sizeText(bytes: record.fileSizeBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    private var actionStrip: some View {
        HStack(spacing: 6) {
            if record.kind == .screenshot {
                stripButton("Open", "pencil") { actions.openRecord(record) }.disabled(isMissing)
            }
            stripButton("Copy", "doc.on.doc") { actions.copyRecord(record) }.disabled(isMissing)
            stripButton("Reveal", "folder") { actions.revealRecord(record) }.disabled(isMissing)
            stripButton("Delete", "trash") { actions.deleteRecord(record) }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .padding(8)
    }

    private func stripButton(_ help: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.borderless)
            .help(help)
    }

    @ViewBuilder private var menuItems: some View {
        if record.kind == .screenshot {
            Button("Open in Editor") { actions.openRecord(record) }.disabled(isMissing)
        } else {
            Button("Open") { actions.openRecord(record) }.disabled(isMissing)
        }
        Button("Copy") { actions.copyRecord(record) }.disabled(isMissing)
        Button("Reveal in Finder") { actions.revealRecord(record) }.disabled(isMissing)
        Divider()
        Button("Remove from History", role: .destructive) { actions.deleteRecord(record) }
    }
}
```

`CaniClip/Hub/HubView.swift`:
```swift
import SwiftUI

struct HubView: View {
    @ObservedObject var viewModel: HubViewModel
    let actions: HubActions

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 16)
            actionRow.padding(.horizontal, 20).padding(.top, 12)
            filterBar.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if viewModel.visibleRecords.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("CaniClip").font(.largeTitle.weight(.semibold))
            Spacer()
            Button(action: actions.openSaveFolder) { Image(systemName: "folder") }.help("Open save folder")
            Button(action: actions.openSettings) { Image(systemName: "gearshape") }.help("Settings")
        }
        .buttonStyle(.bordered)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            ActionTile(title: "Capture Area", symbol: "viewfinder", shortcutName: .captureArea, tint: .blue, action: actions.captureArea)
            ActionTile(title: "Capture Full Screen", symbol: "macwindow", shortcutName: .captureFullScreen, tint: .indigo, action: actions.captureFullScreen)
            ActionTile(title: "Record GIF", symbol: "record.circle", shortcutName: .recordArea, tint: .red, action: actions.recordArea)
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("", selection: $viewModel.filter) {
                ForEach(HubViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            Spacer()
            Text("\(viewModel.visibleRecords.count) item\(viewModel.visibleRecords.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                ForEach(viewModel.sections()) { section in
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(section.records) { record in
                            CaptureCard(record: record,
                                        thumbnailURL: viewModel.library.thumbnailURL(for: record.id),
                                        isMissing: viewModel.isMissing(record),
                                        isSelected: viewModel.selection == record.id,
                                        relativeTime: HubViewModel.relativeTime(record.createdAt, now: Date()),
                                        actions: actions)
                                .onTapGesture(count: 2) { if !viewModel.isMissing(record) { actions.openRecord(record) } }
                                .onTapGesture { viewModel.selection = record.id }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 42)).foregroundStyle(.secondary)
            Text("No captures yet").font(.title3.weight(.medium))
            Text("Use the tiles above or press a shortcut from any app. Screenshots and GIFs you capture will appear here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`CaniClip/Hub/HubWindowController.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
final class HubWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(viewModel: HubViewModel, actions: HubActions) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "CaniClip"
        window.minSize = CGSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CaniClipHub")
        window.contentView = NSHostingView(rootView: HubView(viewModel: viewModel, actions: actions))
        if !window.setFrameUsingName("CaniClipHub") { window.center() }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isShowing: Bool { window?.isVisible ?? false }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Hides without closing, so the window frame and policy are untouched.
    func hideForCapture() {
        window?.orderOut(nil)
    }

    func restoreAfterCapture() {
        window?.orderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
```

- [ ] **Step 6: Menus, status item and coordinator wiring**

Replace `CaniClip/App/MainMenu.swift`:
```swift
import AppKit
import KeyboardShortcuts

/// Target for main-menu items; the delegate keeps one instance alive.
final class MenuActions: NSObject {
    var captureArea: () -> Void = {}
    var captureFullScreen: () -> Void = {}
    var recordArea: () -> Void = {}
    var openHub: () -> Void = {}
    var openSettings: () -> Void = {}

    @objc func captureAreaAction(_ sender: Any?) { captureArea() }
    @objc func captureFullScreenAction(_ sender: Any?) { captureFullScreen() }
    @objc func recordAreaAction(_ sender: Any?) { recordArea() }
    @objc func openHubAction(_ sender: Any?) { openHub() }
    @objc func openSettingsAction(_ sender: Any?) { openSettings() }
}

/// The main menu is visible only while the hub is open (regular activation
/// policy); its key equivalents work in every window at all times.
enum MainMenu {
    static func install(actions: MenuActions) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(MenuActions.openSettingsAction(_:)), keyEquivalent: ",")
        settings.target = actions
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CaniClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        let area = file.addItem(withTitle: "Capture Area", action: #selector(MenuActions.captureAreaAction(_:)), keyEquivalent: "")
        area.target = actions
        area.setShortcut(for: .captureArea)
        let full = file.addItem(withTitle: "Capture Full Screen", action: #selector(MenuActions.captureFullScreenAction(_:)), keyEquivalent: "")
        full.target = actions
        full.setShortcut(for: .captureFullScreen)
        let record = file.addItem(withTitle: "Record Area to GIF", action: #selector(MenuActions.recordAreaAction(_:)), keyEquivalent: "")
        record.target = actions
        record.setShortcut(for: .recordArea)
        file.addItem(.separator())
        let hub = file.addItem(withTitle: "Open CaniClip", action: #selector(MenuActions.openHubAction(_:)), keyEquivalent: "0")
        hub.target = actions
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
```

In `CaniClip/App/StatusItemController.swift`:
- add `var openHub: () -> Void` to `StatusMenuActions` after `recordArea`.
- in `buildMenu()`, after the separator that follows the three capture items and before the Settings item, add:
```swift
        let hub = makeItem("Open CaniClip", #selector(openHub), tag: nil)
        hub.keyEquivalent = "0"
        menu.addItem(hub)
```
- add the selector method next to the others: `@objc private func openHub() { actions.openHub() }`.

In `CaniClip/App/CaptureCoordinator.swift`:
- add stored properties after `private var reportedLibraryFailure = false`:
```swift
    private var hubVisibility = HubVisibilityReducer()
    private var modeObserver: AnyCancellable?
    private lazy var hub: HubWindowController = {
        let controller = HubWindowController(viewModel: HubViewModel(library: library), actions: hubActions())
        controller.onClose = { NSApp.setActivationPolicy(ActivationPolicyRule.policy(openHubWindows: 0)) }
        return controller
    }()
```
  and `import Combine` at the top.
- at the end of `init`, add:
```swift
        modeObserver = appState.$mode.sink { [weak self] mode in
            guard let self else { return }
            switch self.hubVisibility.action(for: mode, hubVisible: self.hub.isShowing) {
            case .hide: self.hub.hideForCapture()
            case .restore: self.hub.restoreAfterCapture()
            case nil: break
            }
        }
```
  Note: `hub` is lazy; reading `hub.isShowing` creates the window controller without showing it, which is fine.
- add the hub section before `func openSettings()`:
```swift
    // MARK: Hub

    func openHub() {
        NSApp.setActivationPolicy(ActivationPolicyRule.policy(openHubWindows: 1))
        hub.present()
    }

    private func hubActions() -> HubActions {
        HubActions(
            captureArea: { [weak self] in self?.handle(.areaScreenshot) },
            captureFullScreen: { [weak self] in self?.handle(.fullScreenScreenshot) },
            recordArea: { [weak self] in self?.handle(.areaRecording) },
            openSettings: { [weak self] in self?.openSettings() },
            openSaveFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.preferences.preferences.saveFolderURL)
            },
            openRecord: { [weak self] in self?.openRecord($0) },
            copyRecord: { [weak self] in self?.copyRecord($0) },
            revealRecord: { [weak self] in
                guard let self, let url = self.library.bestFileURL(for: $0) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            deleteRecord: { [weak self] in self?.deleteRecord($0) }
        )
    }

    private func openRecord(_ record: CaptureRecord) {
        guard let url = library.bestFileURL(for: record) else { return }
        switch record.kind {
        case .screenshot:
            let image = library.image(for: record.id) ?? ThumbnailMaker.firstFrame(ofImageAt: url)
            guard let image else { return }
            openEditor(image, recordID: record.id)
        case .gif:
            NSWorkspace.shared.open(url)
        }
    }

    private func copyRecord(_ record: CaptureRecord) {
        guard let url = library.bestFileURL(for: record) else { return }
        switch record.kind {
        case .screenshot:
            if let image = ThumbnailMaker.firstFrame(ofImageAt: url) { ImageExporter.copyToClipboard(image) }
        case .gif:
            ImageExporter.copyFileToClipboard(url)
        }
    }

    private func deleteRecord(_ record: CaptureRecord) {
        let alert = NSAlert()
        alert.messageText = "Remove this capture from history?"
        alert.informativeText = "Only the history entry and CaniClip's own copy are removed. Files in your save folder are not affected."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try library.delete(id: record.id) } catch { ErrorPresenter.present(error, title: "Could not remove from history") }
    }
```

In `CaniClip/App/AppDelegate.swift` replace the body of `applicationDidFinishLaunching` and add reopen handling:
```swift
    private let menuActions = MenuActions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install(actions: menuActions)

        var coordinatorRef: CaptureCoordinator?
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: { coordinatorRef?.handle(.areaScreenshot) },
            captureFullScreen: { coordinatorRef?.handle(.fullScreenScreenshot) },
            recordArea: { coordinatorRef?.handle(.areaRecording) },
            openHub: { coordinatorRef?.openHub() },
            openSettings: { coordinatorRef?.openSettings() },
            quit: { NSApp.terminate(nil) }
        ))
        let coordinator = CaptureCoordinator(appState: appState, preferences: .shared, statusItem: status)
        coordinatorRef = coordinator
        status.onStopRecordingClicked = { coordinator.stopRecording() }
        status.menuItem(for: .captureArea)?.setShortcut(for: .captureArea)
        status.menuItem(for: .captureFullScreen)?.setShortcut(for: .captureFullScreen)
        status.menuItem(for: .recordArea)?.setShortcut(for: .recordArea)

        menuActions.captureArea = { coordinator.handle(.areaScreenshot) }
        menuActions.captureFullScreen = { coordinator.handle(.fullScreenScreenshot) }
        menuActions.recordArea = { coordinator.handle(.areaRecording) }
        menuActions.openHub = { coordinator.openHub() }
        menuActions.openSettings = { coordinator.openSettings() }

        hotkeys = HotkeyController { kind in coordinator.handle(kind) }
        statusItem = status
        self.coordinator = coordinator

        if !ScreenRecordingPermission.isGranted {
            ScreenRecordingPermission.request()
        }

        let defaults = UserDefaults.standard
        let firstLaunch = !defaults.bool(forKey: "hasLaunchedBefore")
        defaults.set(true, forKey: "hasLaunchedBefore")
        if firstLaunch || PreferencesStore.shared.preferences.openHubAtLaunch {
            coordinator.openHub()
        }
    }

    /// Clicking the Dock icon with no windows reopens the hub.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { coordinator?.openHub() }
        return true
    }
```
(`private let menuActions = MenuActions()` goes with the other stored properties.)

In `CaniClipTests/CaptureCoordinatorTests.swift`, update the `StatusMenuActions(` call to include `openHub: {},` after `recordArea: {},`.

- [ ] **Step 7: Build and run the suite**

Run: `xcodegen generate -q; .superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2`
Expected: `** TEST SUCCEEDED **`, 97 tests, no compile errors.

- [ ] **Step 8: Manual verification**

Run `./scripts/run.sh` (first launch after this build may not count as first launch if `hasLaunchedBefore` is already set; use the menu item). Check:
1. Menu bar → Open CaniClip: the hub opens, a Dock icon appears, and the menu bar shows CaniClip / File / Edit / Window. File lists the three captures with their shortcuts and Open CaniClip ⌘0.
2. The grid shows the captures made so far in this session under Today, thumbnails intact, kind badges correct.
3. Click Capture Area: the hub disappears, the overlay shows; press Esc; the hub comes back. Repeat and drag: the editor opens and the hub comes back behind it. The new shot appears at the top of the grid.
4. Hover a card: the action strip appears. Open reopens the shot in the editor; Save there updates the card's size text. Copy then paste into Preview works. Reveal selects the file. Delete asks for confirmation and removes only the card.
5. Record a short GIF from the tile: the hub hides during the start bar, recording and Saving…, then returns; a GIF card appears; Open launches it in Preview.
6. Close the hub: the Dock icon and menu bar disappear; the menu bar icon still works. Click the Dock icon while the hub is open and closed (reopen).
7. Delete a card's file in Finder, then reopen the hub: the card shows a warning badge and Open, Copy and Reveal are disabled.
8. Settings → General: Keep history → 7 days; Open window at launch toggles on; relaunch via `./scripts/run.sh` opens the hub.

- [ ] **Step 9: Commit**

```bash
git add CaniClip CaniClipTests
git commit -m "feat(hub): capture hub window with history grid, Dock presence and menus

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Smoke test, README and final verification

**Files:**
- Modify: `docs/superpowers/specs/smoke-test.md`
- Modify: `README.md`

- [ ] **Step 1: Extend the smoke test**

Append to `docs/superpowers/specs/smoke-test.md`:
```markdown

## Hub
- [ ] First launch opens the hub; later launches do not unless "Open window at launch" is on.
- [ ] Menu bar → Open CaniClip and File → Open CaniClip (⌘0) show the window with a Dock icon and menus.
- [ ] Tiles capture; the hub hides during the overlay and returns after a capture or a cancelled selection.
- [ ] New screenshots and GIFs appear at the top with correct thumbnails and badges.
- [ ] Card actions: Open, Copy, Reveal, Delete (with confirmation; file in save folder untouched).
- [ ] A record whose file was deleted shows a warning badge with Open/Copy/Reveal disabled.
- [ ] Closing the hub removes the Dock icon; clicking the Dock icon reopens it.
- [ ] Settings → Keep history prunes on next launch; Open window at launch works.
```

- [ ] **Step 2: Update the README**

In `README.md`, after the "Default shortcuts" table add:
```markdown
## Window

Choose **Open CaniClip** from the menu bar icon (or ⌘0 when CaniClip is active) for the
capture hub: large capture tiles plus a history of every screenshot and GIF with reopen,
copy, reveal and remove. History lives in `~/Library/Application Support/CaniClip/Library`
and is pruned after 30 days by default (Settings → General → Keep history).
```
and extend the Layout list with:
```markdown
- `CaniClip/Library/` capture history store; `CaniClip/Hub/` the hub window and view model
```

- [ ] **Step 3: Full verification**

Run:
```bash
(cd core && cargo test 2>&1 | grep -E "^test result: ok. [1-9]")
.superpowers/sdd/2026-10-15-capture-hub/xctest.sh 2>&1 | tail -2
grep "warning:" .superpowers/sdd/2026-10-15-capture-hub/xctest-last.log | grep -vE "KeyboardShortcuts|SourcePackages|appintentsmetadataprocessor" | sort -u
```
Expected: Rust 20 tests pass, `** TEST SUCCEEDED **` with 97 Swift tests, no project warnings. Then run the Hub section of the smoke test.

- [ ] **Step 4: Commit**

```bash
git add README.md docs
git commit -m "docs: hub smoke test section and README window notes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
