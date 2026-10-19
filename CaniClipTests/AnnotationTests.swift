import XCTest
@testable import CaniClip

final class AnnotationTests: XCTestCase {
    func testArrowHitTestAlongTheLine() {
        let a = Annotation(kind: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
        XCTAssertTrue(a.hitTest(CGPoint(x: 50, y: 3), tolerance: 4))
        XCTAssertFalse(a.hitTest(CGPoint(x: 50, y: 30), tolerance: 4))
        XCTAssertFalse(a.hitTest(CGPoint(x: 140, y: 0), tolerance: 4))
    }

    func testRectHitsOnlyTheStroke() {
        let a = Annotation(kind: .rect(CGRect(x: 10, y: 10, width: 100, height: 60)))
        XCTAssertTrue(a.hitTest(CGPoint(x: 10, y: 40), tolerance: 4))   // left edge
        XCTAssertTrue(a.hitTest(CGPoint(x: 60, y: 70), tolerance: 4))   // bottom edge
        XCTAssertFalse(a.hitTest(CGPoint(x: 60, y: 40), tolerance: 4))  // interior
    }

    func testPixelateAndTextHitInside() {
        let p = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 20, height: 20), blockSize: 8))
        XCTAssertTrue(p.hitTest(CGPoint(x: 10, y: 10), tolerance: 0))
        let t = Annotation(kind: .text(origin: CGPoint(x: 5, y: 5), string: "Hello"))
        XCTAssertTrue(t.hitTest(CGPoint(x: 8, y: 10), tolerance: 0))
        XCTAssertFalse(t.hitTest(CGPoint(x: 500, y: 500), tolerance: 0))
    }

    func testPenHitTestUsesSegments() {
        let a = Annotation(kind: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]))
        XCTAssertTrue(a.hitTest(CGPoint(x: 25, y: 25), tolerance: 2))
        XCTAssertFalse(a.hitTest(CGPoint(x: 50, y: 5), tolerance: 2))
    }

    func testTranslatedMovesEverything() {
        let a = Annotation(kind: .ellipse(CGRect(x: 10, y: 10, width: 20, height: 20)))
        let moved = a.translated(by: CGVector(dx: 5, dy: -3))
        XCTAssertEqual(moved.boundingBox, CGRect(x: 15, y: 7, width: 20, height: 20))
        XCTAssertEqual(moved.id, a.id)
        let pen = Annotation(kind: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])).translated(by: CGVector(dx: 1, dy: 1))
        guard case .pen(let pts) = pen.kind else { return XCTFail() }
        XCTAssertEqual(pts, [CGPoint(x: 1, y: 1), CGPoint(x: 11, y: 11)])
    }

    func testCodableRoundTrip() throws {
        let a = Annotation(kind: .arrow(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 3, y: 4)),
                           style: AnnotationStyle(color: .blue, strokeWidth: 6, fontSize: 30))
        let data = try JSONEncoder().encode([a])
        let back = try JSONDecoder().decode([Annotation].self, from: data)
        XCTAssertEqual(back, [a])
    }

    // MARK: Text resizing

    private func text(at origin: CGPoint, size: CGFloat) -> Annotation {
        var style = AnnotationStyle()
        style.fontSize = size
        return Annotation(kind: .text(origin: origin, string: "Hello"), style: style)
    }

    func testDraggingTheBottomRightCornerGrowsTextAndKeepsItsOrigin() {
        let a = text(at: CGPoint(x: 10, y: 20), size: 20)
        let box = a.boundingBox
        let grown = a.resizingText(corner: .bottomRight, to: CGPoint(x: box.minX + box.width * 2, y: box.minY + box.height * 2))
        XCTAssertEqual(grown.style.fontSize, 40, accuracy: 0.01)
        XCTAssertEqual(grown.boundingBox.origin.x, 10, accuracy: 0.01)
        XCTAssertEqual(grown.boundingBox.origin.y, 20, accuracy: 0.01)
    }

    func testDraggingTheTopLeftCornerKeepsTheBottomRightCornerFixed() {
        let a = text(at: CGPoint(x: 100, y: 100), size: 40)
        let box = a.boundingBox
        let shrunk = a.resizingText(corner: .topLeft, to: CGPoint(x: box.midX, y: box.midY))
        XCTAssertEqual(shrunk.style.fontSize, 20, accuracy: 0.01)
        XCTAssertEqual(shrunk.boundingBox.maxX, box.maxX, accuracy: 0.01)
        XCTAssertEqual(shrunk.boundingBox.maxY, box.maxY, accuracy: 0.01)
    }

    func testTextNeverShrinksBelowTheMinimumOrFlips() {
        let a = text(at: CGPoint(x: 50, y: 50), size: 24)
        let crushed = a.resizingText(corner: .bottomRight, to: CGPoint(x: 0, y: 0))
        XCTAssertEqual(crushed.style.fontSize, Annotation.minimumFontSize)
        XCTAssertEqual(crushed.boundingBox.origin.x, 50, accuracy: 0.01)
    }

    func testCornerPointsAreTheBoundingBoxCorners() {
        let a = text(at: CGPoint(x: 10, y: 20), size: 20)
        let box = a.boundingBox
        XCTAssertEqual(a.cornerPoint(.topLeft), CGPoint(x: box.minX, y: box.minY))
        XCTAssertEqual(a.cornerPoint(.bottomRight), CGPoint(x: box.maxX, y: box.maxY))
    }
}
