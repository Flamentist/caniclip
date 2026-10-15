import XCTest
@testable import CaniClip

final class CaptureGeometryTests: XCTestCase {
    func testSourceRectFlipsToTopLeftOriginOnMainDisplay() {
        let display = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let global = CGRect(x: 100, y: 100, width: 200, height: 100) // bottom-left y=100, top y=200
        let src = CaptureGeometry.sourceRect(globalRect: global, display: display)
        XCTAssertEqual(src, CGRect(x: 100, y: 700, width: 200, height: 100))
    }

    func testSourceRectOnSecondaryDisplayLeftOfMain() {
        let display = DisplayGeometry(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
        let global = CGRect(x: -1820, y: 980, width: 100, height: 50)
        let src = CaptureGeometry.sourceRect(globalRect: global, display: display)
        XCTAssertEqual(src, CGRect(x: 100, y: 50, width: 100, height: 50))
    }

    func testPixelSizeUsesBackingScale() {
        let px = CaptureGeometry.pixelSize(pointSize: CGSize(width: 200, height: 100), scale: 2)
        XCTAssertEqual(px.width, 400)
        XCTAssertEqual(px.height, 200)
        let odd = CaptureGeometry.pixelSize(pointSize: CGSize(width: 33.3, height: 10.6), scale: 2)
        XCTAssertEqual(odd.width, 67)
        XCTAssertEqual(odd.height, 21)
    }

    func testScreenContainingPointFallsBackToMain() {
        let screens = NSScreen.screens
        let farAway = CGPoint(x: 1_000_000, y: 1_000_000)
        XCTAssertEqual(CaptureGeometry.screen(containing: farAway, screens: screens), NSScreen.main)
        if let main = NSScreen.main {
            let inside = CGPoint(x: main.frame.midX, y: main.frame.midY)
            XCTAssertEqual(CaptureGeometry.screen(containing: inside, screens: screens), main)
        }
    }
}
