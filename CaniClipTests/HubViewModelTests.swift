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

    private func addShot(_ lib: CaptureLibrary) throws -> CaptureRecord {
        try lib.addScreenshot(TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
    }

    func testSectionsGroupInFirstAppearanceOrderAndEmptyLibraryGivesNone() throws {
        let lib = CaptureLibrary(rootURL: root)
        let vm = HubViewModel(library: lib)
        XCTAssertTrue(vm.sections(now: now, calendar: utc).isEmpty)
        let a = try addShot(lib)
        let b = try addShot(lib)
        let sections = vm.sections(now: Date(), calendar: .current)
        XCTAssertEqual(sections.map(\.title), ["Today"])
        XCTAssertEqual(sections[0].records.map(\.id), [b.id, a.id])
    }

    func testThisWeekBoundaryAndMidnightCrossing() {
        // now is 17:52:03 UTC; 18 hours earlier is the previous calendar day.
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-18 * 3600), now: now, calendar: utc), "Yesterday")
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-7 * 86_400 + 1), now: now, calendar: utc), "This Week")
        XCTAssertEqual(HubViewModel.sectionTitle(for: now.addingTimeInterval(-7 * 86_400), now: now, calendar: utc), "Earlier")
    }

    func testObjectWillChangeFollowsLibraryMutation() throws {
        let lib = CaptureLibrary(rootURL: root)
        let vm = HubViewModel(library: lib)
        var emissions = 0
        let token = vm.objectWillChange.sink { _ in emissions += 1 }
        _ = try addShot(lib)
        XCTAssertGreaterThanOrEqual(emissions, 1)
        token.cancel()
    }

    func testTickUpdatesNowSoRelativeTimesCanRefresh() {
        let lib = CaptureLibrary(rootURL: root)
        let vm = HubViewModel(library: lib)
        var emissions = 0
        let token = vm.objectWillChange.sink { _ in emissions += 1 }
        vm.tick(now: now)
        XCTAssertEqual(vm.now, now)
        XCTAssertEqual(emissions, 1)
        token.cancel()
    }

    func testEmptyStateTextDependsOnFilterAndShortcuts() {
        let shortcuts = HubViewModel.ShortcutLabels(area: "⌘⇧7", fullScreen: "⌘⇧9", record: "⌘⇧8")
        let fresh = HubViewModel.emptyStateText(filter: .all, hasAnyRecords: false, shortcuts: shortcuts)
        XCTAssertEqual(fresh.title, "No captures yet")
        XCTAssertTrue(fresh.message.contains("⌘⇧7") && fresh.message.contains("⌘⇧9") && fresh.message.contains("⌘⇧8"))
        let filtered = HubViewModel.emptyStateText(filter: .gifs, hasAnyRecords: true, shortcuts: shortcuts)
        XCTAssertEqual(filtered.title, "No GIFs yet")
        XCTAssertTrue(filtered.message.contains("All"))
        let shots = HubViewModel.emptyStateText(filter: .screenshots, hasAnyRecords: true, shortcuts: shortcuts)
        XCTAssertEqual(shots.title, "No screenshots yet")
    }

    func testThumbnailIsCachedUntilTheLibraryChanges() throws {
        let lib = CaptureLibrary(rootURL: root)
        let shot = try addShot(lib)
        let vm = HubViewModel(library: lib)
        let first = vm.thumbnail(for: shot)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === vm.thumbnail(for: shot), "same instance while nothing changed")
        let saved = root.appendingPathComponent("saved.png")
        let annotated = TestImages.solid(width: 4, height: 4, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        try ImageExporter.writePNG(annotated, to: saved)
        try lib.markSaved(id: shot.id, to: saved, annotated: annotated)
        XCTAssertFalse(first === vm.thumbnail(for: shot), "a library change invalidates the cache")
    }
}
