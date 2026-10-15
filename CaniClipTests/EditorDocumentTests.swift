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

    func testRasterizeKeepsImageSize() {
        let doc = makeDoc()
        doc.add(Annotation(kind: .arrow(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 14, y: 6))))
        let out = doc.rasterize()!
        XCTAssertEqual(out.width, 16)
        XCTAssertEqual(out.height, 8)
    }
}
