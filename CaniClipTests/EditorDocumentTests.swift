import XCTest
@testable import CaniClip

@MainActor
final class EditorDocumentTests: XCTestCase {
    private func makeDoc() -> EditorDocument {
        EditorDocument(image: TestImages.solid(width: 16, height: 8, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
    }

    func testAddMarksDirtyAndIsUndoable() {
        let doc = makeDoc()
        XCTAssertFalse(doc.isDirty)
        doc.add(Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 4, height: 4))))
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertTrue(doc.isDirty)
        XCTAssertTrue(doc.undoManager.canUndo)
        doc.undoManager.undo()
        XCTAssertEqual(doc.annotations.count, 0)
        XCTAssertTrue(doc.undoManager.canRedo)
        doc.undoManager.redo()
        XCTAssertEqual(doc.annotations.count, 1)
    }

    func testRemoveSelectedOnlyRemovesSelection() {
        let doc = makeDoc()
        let a = Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 4, height: 4)))
        let b = Annotation(kind: .ellipse(CGRect(x: 6, y: 1, width: 4, height: 4)))
        doc.add(a)
        doc.add(b)
        doc.selectedID = a.id
        doc.removeSelected()
        XCTAssertEqual(doc.annotations.map(\.id), [b.id])
        XCTAssertNil(doc.selectedID)
    }

    func testMarkSavedClearsDirtyUntilNextChange() {
        let doc = makeDoc()
        doc.add(Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 4, height: 4))))
        let url = URL(fileURLWithPath: "/tmp/x.png")
        doc.markSaved(to: url)
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.lastSavedURL, url)
        doc.add(Annotation(kind: .rect(CGRect(x: 2, y: 2, width: 2, height: 2))))
        XCTAssertTrue(doc.isDirty)
    }

    func testRemovingAPixelateAnnotationEvictsItsCachedCrop() {
        let doc = makeDoc()
        let pix = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 8, height: 8), blockSize: 4))
        doc.add(pix)
        _ = doc.rasterize()
        XCTAssertEqual(doc.pixelateService.cachedCount, 1)
        doc.selectedID = pix.id
        doc.removeSelected()
        XCTAssertEqual(doc.pixelateService.cachedCount, 0)
    }

    func testRasterizeKeepsImageSize() {
        let doc = makeDoc()
        doc.add(Annotation(kind: .arrow(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 14, y: 6))))
        let out = doc.rasterize()!
        XCTAssertEqual(out.width, 16)
        XCTAssertEqual(out.height, 8)
    }

    /// Redaction blocks must look as coarse on a big photo shown shrunk as on a screenshot.
    func testPixelateBlockSizeFollowsTheStyleScale() {
        let image = TestImages.solid(width: 16, height: 8, color: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(EditorDocument(image: image).pixelateBlockSize, 12)
        XCTAssertEqual(EditorDocument(image: image, styleScale: 2).pixelateBlockSize, 24)
    }

    // MARK: Text size

    private func docWithText() -> (EditorDocument, Annotation) {
        let doc = makeDoc()
        let text = Annotation(kind: .text(origin: CGPoint(x: 2, y: 2), string: "A"))
        doc.setAnnotationsWithoutUndo([text])
        return (doc, text)
    }

    func testTextSizeResizesTheSelectedTextAndIsUndoable() {
        let (doc, text) = docWithText()
        doc.selectedID = text.id
        doc.setTextSize(48)
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 48)
        XCTAssertEqual(doc.style.fontSize, 48, "new text uses the size too")
        XCTAssertEqual(doc.undoManager.undoActionName, "Text Size")
        doc.undoManager.undo()
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 24)
    }

    func testTextSizeWithNothingSelectedOnlySetsTheSizeForNewText() {
        let (doc, _) = docWithText()
        doc.setTextSize(64)
        XCTAssertEqual(doc.style.fontSize, 64)
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 24)
        XCTAssertFalse(doc.undoManager.canUndo)
    }

    func testTextControlsShowForTheTextToolOrASelectedText() {
        let (doc, text) = docWithText()
        doc.tool = .arrow
        XCTAssertFalse(doc.isEditingText)
        doc.tool = .text
        XCTAssertTrue(doc.isEditingText)
        doc.tool = .select
        doc.selectedID = text.id
        XCTAssertTrue(doc.isEditingText)
        let box = Annotation(kind: .rect(CGRect(x: 1, y: 1, width: 4, height: 4)))
        doc.setAnnotationsWithoutUndo([text, box])
        doc.selectedID = box.id
        XCTAssertFalse(doc.isEditingText)
    }
}
