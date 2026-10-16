import XCTest
import ScreenCaptureKit
@testable import CaniClip

@MainActor
final class SelectionViewTests: XCTestCase {
    func testOverlayAcceptsTheActivatingClickAsADragStart() {
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    /// Hosts a view in a window and plays a mouse press from `start` to `end`.
    private func select(from start: CGPoint, to end: CGPoint, clickSelectsScreen: Bool) -> CGRect?? {
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 2)
        view.clickSelectsScreen = clickSelectsScreen
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        var result: CGRect??
        view.onFinished = { result = .some($0) }
        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, start))
        if end != start { view.mouseDragged(with: mouse(.leftMouseDragged, end)) }
        view.mouseUp(with: mouse(.leftMouseUp, end))
        window.close()
        return result
    }

    func testClickWithoutDragCancelsByDefault() {
        let result = select(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), clickSelectsScreen: false)
        XCTAssertEqual(result, .some(nil))
    }

    func testClickWithoutDragSelectsTheWholeScreenWhenAllowed() {
        let result = select(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), clickSelectsScreen: true)
        XCTAssertEqual(result, .some(CGRect(x: 0, y: 0, width: 400, height: 300)))
    }

    func testDragSelectsTheDraggedAreaEvenWhenClicksSelectTheScreen() {
        let result = select(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 150, y: 140), clickSelectsScreen: true)
        XCTAssertEqual(result, .some(CGRect(x: 50, y: 40, width: 100, height: 100)))
    }
}

final class CaptureFailureTests: XCTestCase {
    func testUserDeclinedStreamErrorIsAPermissionProblem() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        XCTAssertTrue(CaptureFailure.isPermissionDenied(error))
    }

    func testOtherErrorsAreNotPermissionProblems() {
        XCTAssertFalse(CaptureFailure.isPermissionDenied(CaptureError.displayNotFound))
        let other = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noDisplayList.rawValue)
        XCTAssertFalse(CaptureFailure.isPermissionDenied(other))
    }
}
