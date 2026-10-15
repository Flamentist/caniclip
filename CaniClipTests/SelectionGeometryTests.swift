import XCTest
@testable import CaniClip

final class SelectionGeometryTests: XCTestCase {
    func testReverseDragIsNormalised() {
        let r = SelectionGeometry.rect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), constrainSquare: false)
        XCTAssertEqual(r, CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    func testShiftConstrainsToSquareUsingLargerSide() {
        let r = SelectionGeometry.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40), constrainSquare: true)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 100, height: 100))
        let up = SelectionGeometry.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: -30, y: 80), constrainSquare: true)
        XCTAssertEqual(up, CGRect(x: -80, y: 0, width: 80, height: 80))
    }

    func testClickOrJitterIsNotUsable() {
        XCTAssertFalse(SelectionGeometry.isUsable(CGRect(x: 10, y: 10, width: 0, height: 0)))
        XCTAssertFalse(SelectionGeometry.isUsable(CGRect(x: 10, y: 10, width: 1, height: 50)))
        XCTAssertTrue(SelectionGeometry.isUsable(CGRect(x: 10, y: 10, width: 2, height: 2)))
    }

    func testSizeLabelReportsPixelsAtBackingScale() {
        XCTAssertEqual(SelectionGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 120.4, height: 80), scale: 2), "241 × 160")
        XCTAssertEqual(SelectionGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 120, height: 80), scale: 1), "120 × 80")
    }
}
