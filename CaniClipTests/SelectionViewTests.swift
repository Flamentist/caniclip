import XCTest
import ScreenCaptureKit
@testable import CaniClip

@MainActor
final class SelectionViewTests: XCTestCase {
    func testOverlayAcceptsTheActivatingClickAsADragStart() {
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
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
