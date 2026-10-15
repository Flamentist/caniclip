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

    func testClosedHubIsNeverRestored() {
        var r = HubVisibilityReducer()
        XCTAssertEqual(r.action(for: .selecting(.areaRecording), hubVisible: true), .hide)
        r.hubClosed()
        XCTAssertFalse(r.hiddenForCapture)
        XCTAssertNil(r.action(for: .idle, hubVisible: false), "a closed hub is never restored")
    }

    func testHubClosedWithoutHidingIsHarmless() {
        var r = HubVisibilityReducer()
        r.hubClosed()
        XCTAssertNil(r.action(for: .idle, hubVisible: false))
    }

    @MainActor
    func testHubIsShowingOnlyWhileVisibleAndNotMiniaturised() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caniclip-hubwin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = HubViewModel(library: CaptureLibrary(rootURL: root))
        let noop = HubActions(captureArea: {}, captureFullScreen: {}, recordArea: {}, openSettings: {}, openSaveFolder: {},
                              openRecord: { _ in }, copyRecord: { _ in }, revealRecord: { _ in }, deleteRecord: { _ in })
        let hub = HubWindowController(viewModel: vm, actions: noop)
        XCTAssertFalse(hub.isShowing)
        hub.window?.orderFront(nil)
        XCTAssertTrue(hub.isShowing)
        hub.window?.orderOut(nil)
        XCTAssertFalse(hub.isShowing)
        // Miniaturising has no effect on a headless window in the test host, so the
        // Dock round-trip is covered by the smoke test, not here.
        hub.close()
    }
}
