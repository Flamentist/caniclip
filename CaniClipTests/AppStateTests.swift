import XCTest
@testable import CaniClip

@MainActor
final class AppStateTests: XCTestCase {
    func testIdleStartsSelectionForAreaKinds() {
        let s = AppState()
        XCTAssertEqual(s.action(for: .areaScreenshot), .startSelection(.areaScreenshot))
        XCTAssertEqual(s.action(for: .areaRecording), .startSelection(.areaRecording))
    }

    func testIdleCapturesFullScreenImmediately() {
        let s = AppState()
        XCTAssertEqual(s.action(for: .fullScreenScreenshot), .captureFullScreenNow)
    }

    func testRecordHotkeyWhileRecordingStops() {
        let s = AppState()
        s.transition(to: .recording)
        XCTAssertEqual(s.action(for: .areaRecording), .stopRecording)
    }

    func testOtherHotkeysWhileRecordingAreIgnored() {
        let s = AppState()
        s.transition(to: .recording)
        XCTAssertEqual(s.action(for: .areaScreenshot), .ignore)
        XCTAssertEqual(s.action(for: .fullScreenScreenshot), .ignore)
    }

    func testHotkeysWhileSelectingAreIgnored() {
        let s = AppState()
        s.transition(to: .selecting(.areaScreenshot))
        XCTAssertEqual(s.action(for: .areaScreenshot), .ignore)
        XCTAssertEqual(s.action(for: .areaRecording), .ignore)
        XCTAssertEqual(s.action(for: .fullScreenScreenshot), .ignore)
    }

    func testEditingAllowsNewCaptures() {
        let s = AppState()
        s.transition(to: .editing)
        XCTAssertEqual(s.action(for: .areaScreenshot), .startSelection(.areaScreenshot))
        XCTAssertEqual(s.action(for: .fullScreenScreenshot), .captureFullScreenNow)
    }

    func testHotkeysWhileFinishingAreIgnored() {
        let s = AppState()
        s.transition(to: .finishing)
        XCTAssertEqual(s.action(for: .areaRecording), .ignore)
        XCTAssertEqual(s.action(for: .areaScreenshot), .ignore)
        XCTAssertEqual(s.action(for: .fullScreenScreenshot), .ignore)
    }
}
