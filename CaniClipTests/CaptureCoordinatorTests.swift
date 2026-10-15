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

    private func makeCoordinator(saveFolder: String) -> CaptureCoordinator {
        let defaults = UserDefaults(suiteName: "caniclip.tests.coordinator.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        store.preferences.saveFolderPath = saveFolder
        store.preferences.afterCapture = .saveToFolder
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: {}, captureFullScreen: {}, recordArea: {}, openSettings: {}, quit: {}))
        return CaptureCoordinator(appState: AppState(), preferences: store, statusItem: status)
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
}
