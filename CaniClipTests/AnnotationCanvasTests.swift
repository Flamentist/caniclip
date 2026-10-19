import XCTest
@testable import CaniClip

/// Drives the canvas with real mouse events. The canvas is sized to the image,
/// so view points and image pixels coincide (scale 1).
@MainActor
final class AnnotationCanvasTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)

    private func makeCanvas(_ doc: EditorDocument) -> (AnnotationCanvasView, NSWindow) {
        let canvas = AnnotationCanvasView(document: doc)
        canvas.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        addTeardownBlock { window.close() }
        return (canvas, window)
    }

    /// `p` is in image pixels (top-left origin); windows count from the bottom.
    private func mouse(_ type: NSEvent.EventType, at p: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: size.height - p.y), modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func drag(_ canvas: AnnotationCanvasView, _ window: NSWindow, from a: CGPoint, to b: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: a, in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: b, in: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: b, in: window))
    }

    private func docWithText(tool: EditorTool) -> (EditorDocument, Annotation) {
        let doc = EditorDocument(image: TestImages.solid(width: 400, height: 300, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        var style = AnnotationStyle()
        style.fontSize = 20
        let text = Annotation(kind: .text(origin: CGPoint(x: 50, y: 50), string: "Hi"), style: style)
        doc.setAnnotationsWithoutUndo([text])   // setup is not an undo step
        doc.selectedID = text.id
        doc.tool = tool
        return (doc, text)
    }

    func testDraggingASelectedTextsCornerResizesItAndIsUndoable() {
        let (doc, text) = docWithText(tool: .select)
        let (canvas, window) = makeCanvas(doc)
        let corner = text.cornerPoint(.bottomRight)
        let box = text.boundingBox
        drag(canvas, window, from: corner, to: CGPoint(x: box.minX + box.width * 2, y: box.minY + box.height * 2))
        XCTAssertEqual(doc.annotations.first?.style.fontSize ?? 0, 40, accuracy: 0.5)
        XCTAssertEqual(doc.undoManager.undoActionName, "Resize")
        doc.undoManager.undo()
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 20)
    }

    func testHandlesWorkWhileTheTextToolIsActive() {
        let (doc, text) = docWithText(tool: .text)
        let (canvas, window) = makeCanvas(doc)
        drag(canvas, window, from: text.cornerPoint(.topLeft), to: CGPoint(x: text.boundingBox.midX, y: text.boundingBox.midY))
        XCTAssertEqual(doc.annotations.count, 1, "grabbing a handle must not start a new text")
        XCTAssertEqual(doc.annotations.first?.style.fontSize ?? 0, 10, accuracy: 0.5)
        XCTAssertFalse(canvas.subviews.contains { $0 is NSTextField })
    }

    func testDraggingTheMiddleOfATextStillMovesIt() {
        let (doc, text) = docWithText(tool: .select)
        let (canvas, window) = makeCanvas(doc)
        let mid = CGPoint(x: text.boundingBox.midX, y: text.boundingBox.midY)
        drag(canvas, window, from: mid, to: CGPoint(x: mid.x + 30, y: mid.y))
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 20)
        XCTAssertEqual(doc.annotations.first?.boundingBox.minX ?? 0, 80, accuracy: 0.5)
    }

    func testNewTextIsSelectedSoItsHandlesShowRightAway() throws {
        let doc = EditorDocument(image: TestImages.solid(width: 400, height: 300, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        doc.tool = .text
        let (canvas, window) = makeCanvas(doc)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), in: window))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "Note"
        // Return commits the text, as when typing.
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(doc.annotations.count, 1, "Return must add the text once")
        XCTAssertEqual(doc.selectedID, doc.annotations.first?.id)
    }

    func testStartingANewTextDeselectsThePreviousOne() throws {
        let (doc, _) = docWithText(tool: .text)
        let (canvas, window) = makeCanvas(doc)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 250, y: 200), in: window))
        XCTAssertNil(doc.selectedID, "the size menu must not resize the previous text")
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        doc.setTextSize(48)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(field.font?.pointSize ?? 0, 48, accuracy: 0.5, "the field being typed in follows the size")
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 20)
    }

    func testSmallTextCanStillBeMovedFromItsMiddle() {
        let doc = EditorDocument(image: TestImages.solid(width: 400, height: 300, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        var style = AnnotationStyle()
        style.fontSize = 8
        let tiny = Annotation(kind: .text(origin: CGPoint(x: 100, y: 100), string: "i"), style: style)
        doc.setAnnotationsWithoutUndo([tiny])
        doc.selectedID = tiny.id
        doc.tool = .select
        let (canvas, window) = makeCanvas(doc)
        let mid = CGPoint(x: tiny.boundingBox.midX, y: tiny.boundingBox.midY)
        drag(canvas, window, from: mid, to: CGPoint(x: mid.x + 20, y: mid.y))
        XCTAssertEqual(doc.annotations.first?.style.fontSize, 8, "a click in the middle moves, it doesn't resize")
        XCTAssertEqual(doc.annotations.first?.boundingBox.minX ?? 0, 120, accuracy: 0.5)
    }

    func testEscapeLeavesNothingSelected() throws {
        let doc = EditorDocument(image: TestImages.solid(width: 400, height: 300, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        doc.tool = .text
        let (canvas, window) = makeCanvas(doc)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), in: window))
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first).stringValue = "Note"
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: escape)
        XCTAssertNil(doc.selectedID)
    }
}
