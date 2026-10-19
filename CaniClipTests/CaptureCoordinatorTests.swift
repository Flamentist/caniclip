import XCTest
@testable import CaniClip

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private var presented: [(String, String)] = []

    override func setUp() {
        presented = []
        ErrorPresenter.handler = { [weak self] error, title in self?.presented.append((title, error.localizedDescription)) }
    }

    override func tearDown() {
        ErrorPresenter.handler = ErrorPresenter.alertHandler
        if let libraryRoot { try? FileManager.default.removeItem(at: libraryRoot) }
    }

    private var libraryRoot: URL!

    private func makeCoordinator(saveFolder: String, afterCapture: AfterCaptureAction = .saveToFolder,
                                 libraryRoot: URL? = nil) -> CaptureCoordinator {
        let defaults = UserDefaults(suiteName: "caniclip.tests.coordinator.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        store.preferences.saveFolderPath = saveFolder
        store.preferences.afterCapture = afterCapture
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: {}, captureFullScreen: {}, recordArea: {}, openHub: {}, openSettings: {}, quit: {}))
        self.libraryRoot = libraryRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-coord-lib-\(UUID().uuidString)")
        let library = CaptureLibrary(rootURL: self.libraryRoot)
        return CaptureCoordinator(appState: AppState(), preferences: store, statusItem: status, library: library)
    }

    func testSaveToFolderFailureFallsBackToTheEditor() {
        let coordinator = makeCoordinator(saveFolder: "/nonexistent-caniclip-\(UUID().uuidString)")
        let image = TestImages.solid(width: 8, height: 8, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        coordinator.deliverScreenshot(image)
        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual(coordinator.openEditorCount, 1, "the screenshot must not be lost")
        XCTAssertEqual(coordinator.appState.mode, .editing)
        coordinator.closeAllEditorsForTesting()
    }

    func testTerminationIsBlockedWhenAnEditorCancelsTheUnsavedPrompt() {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        let image = TestImages.solid(width: 8, height: 8, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        coordinator.openEditor(image)
        let editor = coordinator.editorsForTesting[0]
        editor.editorDocument.add(Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 3, height: 3))))
        editor.unsavedPrompt = { .cancel }
        XCTAssertFalse(coordinator.editorsAllowTermination())
        editor.unsavedPrompt = { .discard }
        XCTAssertTrue(coordinator.editorsAllowTermination())
        coordinator.closeAllEditorsForTesting()
    }

    func testTerminationIsAllowedWhenEditorsAreClean() {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        let image = TestImages.solid(width: 8, height: 8, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        coordinator.openEditor(image)
        XCTAssertTrue(coordinator.editorsAllowTermination())
        coordinator.closeAllEditorsForTesting()
    }

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

    func testPruneRunsAfterEachAddition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-coord-prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // 20 days old: survives the launch-time prune (default 30 days) but not a 7-day window.
        let old = CaptureRecord(id: UUID(), kind: .screenshot, createdAt: Date().addingTimeInterval(-20 * 86_400),
                                pixelWidth: 4, pixelHeight: 3, fileSizeBytes: 12, savedPath: nil,
                                hasLibraryAsset: false, durationSeconds: nil, frameCount: nil)
        try JSONEncoder().encode([old]).write(to: root.appendingPathComponent("index.json"))
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .copyToClipboard, libraryRoot: root)
        XCTAssertEqual(coordinator.library.records.map(\.id), [old.id], "launch prune keeps it")
        coordinator.preferences.preferences.historyRetentionDays = 7
        let image = TestImages.solid(width: 10, height: 6, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        coordinator.deliverScreenshot(image)
        XCTAssertEqual(coordinator.library.records.count, 1)
        XCTAssertNotEqual(coordinator.library.records.first?.id, old.id, "the old record was pruned after the addition")
    }

    // MARK: Import

    private func writePNG(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try ImageExporter.writePNG(TestImages.solid(width: 24, height: 12, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)), to: url)
        return url
    }

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-coord-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOpeningAFileOpensATitledEditorAndRecordsHistory() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .copyToClipboard)
        coordinator.openFiles([try writePNG("diagram.png", in: try tempFolder())])
        XCTAssertEqual(coordinator.openEditorCount, 1, "imports open the editor whatever After capture says")
        XCTAssertEqual(coordinator.editorsForTesting.first?.window?.title, "diagram.png")
        XCTAssertEqual(coordinator.library.records.count, 1)
        XCTAssertEqual(coordinator.appState.mode, .editing)
        XCTAssertTrue(presented.isEmpty)
        coordinator.closeAllEditorsForTesting()
    }

    func testPastingWithNoImageReportsAndOpensNothing() {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("caniclip.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        coordinator.pasteImage(from: pasteboard)
        XCTAssertEqual(presented.map(\.0), ["Could not paste"])
        XCTAssertEqual(presented.map(\.1), ["There's no image on the clipboard"])
        XCTAssertEqual(coordinator.openEditorCount, 0)
        XCTAssertEqual(coordinator.appState.mode, .idle)
    }

    func testOpeningANonImageFileReports() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        let text = try tempFolder().appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: text)
        coordinator.openFiles([text])
        XCTAssertEqual(presented.map(\.0), ["Could not open"])
        XCTAssertEqual(coordinator.openEditorCount, 0)
    }

    func testOnlyTheFirstOfSeveralFilesOpens() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        let folder = try tempFolder()
        coordinator.openFiles([try writePNG("one.png", in: folder), try writePNG("two.png", in: folder)])
        XCTAssertEqual(coordinator.openEditorCount, 1)
        XCTAssertEqual(coordinator.editorsForTesting.first?.window?.title, "one.png")
        coordinator.closeAllEditorsForTesting()
    }

    func testImportDuringARecordingLeavesTheRecordingInCharge() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        coordinator.appState.transition(to: .recording)
        coordinator.openFiles([try writePNG("mid.png", in: try tempFolder())])
        XCTAssertEqual(coordinator.openEditorCount, 1)
        XCTAssertEqual(coordinator.appState.mode, .recording)
        XCTAssertEqual(coordinator.appState.action(for: .areaRecording), .stopRecording)
        coordinator.editorsForTesting[0].close()
        XCTAssertEqual(coordinator.appState.mode, .recording, "closing the editor must not end the recording state")
    }

    // MARK: Reopening

    private let box = Annotation(kind: .rect(CGRect(x: 2, y: 2, width: 6, height: 4)))

    /// Captures into the editor, adds a box, then closes choosing Don't Save.
    private func captureEditAndClose(_ coordinator: CaptureCoordinator) throws -> CaptureRecord {
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let editor = try XCTUnwrap(coordinator.editorsForTesting.first)
        editor.editorDocument.add(box)
        editor.unsavedPrompt = { .discard }
        editor.close()
        return try XCTUnwrap(coordinator.library.records.first)
    }

    func testReopeningACaptureBringsBackItsEditsStillEditable() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .openEditor)
        let record = try captureEditAndClose(coordinator)
        XCTAssertEqual(coordinator.openEditorCount, 0)
        coordinator.openRecord(record)
        let reopened = try XCTUnwrap(coordinator.editorsForTesting.first)
        XCTAssertEqual(reopened.editorDocument.annotations, [box], "Don't Save still keeps the edits in history")
        XCTAssertFalse(reopened.editorDocument.isDirty)
        coordinator.closeAllEditorsForTesting()
    }

    func testReopeningAnOpenCaptureBringsItsWindowForward() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .openEditor)
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let record = try XCTUnwrap(coordinator.library.records.first)
        coordinator.openRecord(record)
        XCTAssertEqual(coordinator.openEditorCount, 1)
        coordinator.closeAllEditorsForTesting()
    }

    func testReopenedImportKeepsItsTitleAndAnnotationScale() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory())
        coordinator.openFiles([try writePNG("photo.png", in: try tempFolder())])
        let first = try XCTUnwrap(coordinator.editorsForTesting.first)
        let scale = first.editorDocument.styleScale
        first.close()
        coordinator.openRecord(try XCTUnwrap(coordinator.library.records.first))
        let reopened = try XCTUnwrap(coordinator.editorsForTesting.first)
        XCTAssertEqual(reopened.window?.title, "photo.png")
        XCTAssertEqual(reopened.editorDocument.styleScale, scale)
        coordinator.closeAllEditorsForTesting()
    }

    func testSavingAReopenedCaptureOverwritesItsEarlierFile() throws {
        let folder = try tempFolder()
        let coordinator = makeCoordinator(saveFolder: folder.path, afterCapture: .openEditor)
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let editor = try XCTUnwrap(coordinator.editorsForTesting.first)
        editor.editorDocument.add(box)
        let saved = try editor.save()
        editor.close()
        coordinator.openRecord(try XCTUnwrap(coordinator.library.records.first))
        let reopened = try XCTUnwrap(coordinator.editorsForTesting.first)
        XCTAssertEqual(reopened.editorDocument.lastSavedURL, saved)
        coordinator.closeAllEditorsForTesting()
    }

    // MARK: Review fixes

    func testQuittingWithDontSaveStillKeepsTheEdits() throws {
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .openEditor)
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let editor = try XCTUnwrap(coordinator.editorsForTesting.first)
        editor.editorDocument.add(box)
        editor.unsavedPrompt = { .discard }
        XCTAssertTrue(coordinator.editorsAllowTermination())
        let id = try XCTUnwrap(coordinator.library.records.first?.id)
        XCTAssertEqual(coordinator.library.edits(for: id), [box])
        coordinator.closeAllEditorsForTesting()
    }

    /// Saved before edits were kept: the saved file holds annotations we can't restore,
    /// so Save must not overwrite it with the bare original.
    func testReopeningASavedCaptureWithoutStoredEditsSavesANewFile() throws {
        let folder = try tempFolder()
        let coordinator = makeCoordinator(saveFolder: folder.path, afterCapture: .openEditor)
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let editor = try XCTUnwrap(coordinator.editorsForTesting.first)
        editor.editorDocument.add(box)
        _ = try editor.save()
        coordinator.closeAllEditorsForTesting()   // closes without storing edits, like an older version
        let record = try XCTUnwrap(coordinator.library.records.first)
        try? FileManager.default.removeItem(at: coordinator.library.editsURL(for: record.id))
        coordinator.openRecord(record)
        XCTAssertNil(try XCTUnwrap(coordinator.editorsForTesting.first).editorDocument.lastSavedURL)
        coordinator.closeAllEditorsForTesting()
    }

    func testHistoryCleanupSparesCapturesWithAnOpenEditor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-coord-spare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = makeCoordinator(saveFolder: NSTemporaryDirectory(), afterCapture: .openEditor, libraryRoot: root)
        coordinator.deliverScreenshot(TestImages.solid(width: 20, height: 12, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let open = try XCTUnwrap(coordinator.library.records.first)
        // Retention so short that the next capture's cleanup would remove the open one.
        try coordinator.library.prune(olderThan: 1, now: Date().addingTimeInterval(2 * 86_400), keeping: [open.id])
        XCTAssertTrue(coordinator.library.records.contains { $0.id == open.id })
        try coordinator.library.prune(olderThan: 1, now: Date().addingTimeInterval(2 * 86_400), keeping: [])
        XCTAssertFalse(coordinator.library.records.contains { $0.id == open.id })
        XCTAssertEqual(coordinator.openRecordIDs, [open.id])
        coordinator.closeAllEditorsForTesting()
    }
}
