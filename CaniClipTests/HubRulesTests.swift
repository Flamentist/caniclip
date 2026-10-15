import XCTest
@testable import CaniClip

final class HubRulesTests: XCTestCase {
    func testPolicyIsRegularOnlyWhileAHubWindowIsOpen() {
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 0), .accessory)
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 1), .regular)
        XCTAssertEqual(ActivationPolicyRule.policy(openHubWindows: 2), .regular)
    }

    func testHubHidesForCaptureAndRestoresEvenWhenCancelled() {
        var r = HubVisibilityReducer()
        XCTAssertEqual(r.action(for: .selecting(.areaScreenshot), hubVisible: true), .hide)
        XCTAssertTrue(r.hiddenForCapture)
        XCTAssertNil(r.action(for: .selecting(.areaScreenshot), hubVisible: false), "already hidden; no second hide")
        XCTAssertEqual(r.action(for: .idle, hubVisible: false), .restore, "cancelled selection restores the hub")
        XCTAssertFalse(r.hiddenForCapture)
    }

    func testHubThatWasNotVisibleIsNeverRestored() {
        var r = HubVisibilityReducer()
        XCTAssertNil(r.action(for: .selecting(.areaRecording), hubVisible: false))
        XCTAssertNil(r.action(for: .recording, hubVisible: false))
        XCTAssertNil(r.action(for: .idle, hubVisible: false))
    }

    func testHubStaysHiddenThroughRecordingAndFinishing() {
        var r = HubVisibilityReducer()
        XCTAssertEqual(r.action(for: .selecting(.areaRecording), hubVisible: true), .hide)
        XCTAssertNil(r.action(for: .recording, hubVisible: false))
        XCTAssertNil(r.action(for: .finishing, hubVisible: false))
        XCTAssertEqual(r.action(for: .idle, hubVisible: false), .restore)
    }

    func testEditingAfterCaptureRestoresTheHub() {
        var r = HubVisibilityReducer()
        _ = r.action(for: .selecting(.areaScreenshot), hubVisible: true)
        XCTAssertEqual(r.action(for: .editing, hubVisible: false), .restore)
    }
}
