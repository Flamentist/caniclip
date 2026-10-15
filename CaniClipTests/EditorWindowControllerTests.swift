import XCTest
@testable import CaniClip

@MainActor
final class EditorWindowControllerTests: XCTestCase {
    func testSaveWritesPNGIntoPreferredFolderAndClearsDirty() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let defaults = UserDefaults(suiteName: "caniclip.tests.editor.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        store.preferences.saveFolderPath = folder.path

        let image = TestImages.solid(width: 20, height: 10, color: CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        let controller = EditorWindowController(image: image, preferences: store)
        controller.editorDocument.add(Annotation(kind: .rect(CGRect(x: 2, y: 2, width: 5, height: 5))))
        XCTAssertTrue(controller.editorDocument.isDirty)

        let url = try controller.save()
        XCTAssertEqual(url.deletingLastPathComponent().path, folder.path)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("CaniClip "))
        XCTAssertTrue(url.pathExtension == "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(controller.editorDocument.isDirty)

        // Saving again overwrites the same file instead of creating a second one.
        controller.editorDocument.add(Annotation(kind: .ellipse(CGRect(x: 1, y: 1, width: 3, height: 3))))
        let again = try controller.save()
        XCTAssertEqual(again, url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        controller.close()
    }
}
