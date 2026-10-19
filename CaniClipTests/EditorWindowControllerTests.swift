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

    private func makeStore(folder: URL) -> PreferencesStore {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "caniclip.tests.editor.\(UUID().uuidString)")!, key: "prefs")
        store.preferences.saveFolderPath = folder.path
        return store
    }

    func testLayoutFitsALargeImageToEightyPercentOfTheScreen() {
        let layout = EditorWindowController.layout(imagePixels: CGSize(width: 8000, height: 4000), scale: 2,
                                                   screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(layout.fit, 1152.0 / 4000.0, accuracy: 0.0001)
        XCTAssertEqual(layout.content.width, 1152, accuracy: 0.5)
    }

    func testLayoutKeepsSmallImagesAtFullSize() {
        let layout = EditorWindowController.layout(imagePixels: CGSize(width: 400, height: 200), scale: 2,
                                                   screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(layout.fit, 1)
        XCTAssertEqual(layout.content, CGSize(width: 480, height: 320))
    }

    func testImportedEditorUsesItsTitleAndScaledStyle() {
        let image = TestImages.solid(width: 6000, height: 3000, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let controller = EditorWindowController(image: image, preferences: makeStore(folder: FileManager.default.temporaryDirectory),
                                                title: "photo.jpg", scalesStyleToFit: true)
        defer { controller.close() }
        let doc = controller.editorDocument
        XCTAssertEqual(controller.window?.title, "photo.jpg")
        XCTAssertGreaterThan(doc.styleScale, 1)
        XCTAssertEqual(doc.style.strokeWidth, (4 * doc.styleScale).rounded())
        XCTAssertEqual(doc.style.fontSize, (24 * doc.styleScale).rounded())
    }

    func testScreenshotEditorKeepsDefaultStyle() {
        let image = TestImages.solid(width: 6000, height: 3000, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let controller = EditorWindowController(image: image, preferences: makeStore(folder: FileManager.default.temporaryDirectory))
        defer { controller.close() }
        XCTAssertEqual(controller.window?.title, "Screenshot")
        XCTAssertEqual(controller.editorDocument.styleScale, 1)
        XCTAssertEqual(controller.editorDocument.style.strokeWidth, 4)
        XCTAssertEqual(controller.editorDocument.style.fontSize, 24)
    }

    func testSaveNeverWritesToTheOpenedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let saveFolder = root.appendingPathComponent("saves")
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.png")
        try ImageExporter.writePNG(TestImages.solid(width: 30, height: 20, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)), to: original)
        let before = try Data(contentsOf: original)

        let imported = try ImageImporter.image(contentsOf: original)
        let controller = EditorWindowController(image: imported.image, preferences: makeStore(folder: saveFolder),
                                                title: imported.title, scalesStyleToFit: true)
        defer { controller.close() }
        controller.editorDocument.add(Annotation(kind: .rect(CGRect(x: 2, y: 2, width: 5, height: 5))))
        let saved = try controller.save()
        XCTAssertNotEqual(saved.standardizedFileURL, original.standardizedFileURL)
        XCTAssertEqual(saved.deletingLastPathComponent().standardizedFileURL, saveFolder.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: original), before)
    }
}
