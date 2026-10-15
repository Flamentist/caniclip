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
}
