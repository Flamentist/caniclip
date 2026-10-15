import XCTest
@testable import CaniClip

final class PanelPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testPlacesBelowRegionCentred() {
        let region = CGRect(x: 400, y: 400, width: 300, height: 200)
        let o = PanelPlacement.origin(panelSize: CGSize(width: 220, height: 44), nearRegion: region, visibleFrame: visible, gap: 12)
        XCTAssertEqual(o.x, 440)              // 400 + 150 - 110
        XCTAssertEqual(o.y, 400 - 12 - 44)
    }

    func testFlipsAboveWhenNoRoomBelow() {
        let region = CGRect(x: 400, y: 10, width: 300, height: 200)
        let o = PanelPlacement.origin(panelSize: CGSize(width: 220, height: 44), nearRegion: region, visibleFrame: visible, gap: 12)
        XCTAssertEqual(o.y, 210 + 12)
    }

    func testClampsHorizontallyInsideVisibleFrame() {
        let region = CGRect(x: 1400, y: 400, width: 30, height: 30)
        let o = PanelPlacement.origin(panelSize: CGSize(width: 220, height: 44), nearRegion: region, visibleFrame: visible, gap: 12)
        XCTAssertEqual(o.x, 1440 - 220 - 8)
        let left = PanelPlacement.origin(panelSize: CGSize(width: 220, height: 44), nearRegion: CGRect(x: 0, y: 400, width: 30, height: 30), visibleFrame: visible, gap: 12)
        XCTAssertEqual(left.x, 8)
    }
}
