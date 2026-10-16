import XCTest
import SwiftUI
@testable import CaniClip

@MainActor
final class RecordStartViewTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
    }

    private func makeStore() -> PreferencesStore {
        let defaults = UserDefaults(suiteName: "caniclip.tests.startbar.\(UUID().uuidString)")!
        return PreferencesStore(defaults: defaults, key: "prefs")
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    /// Hosts the bar in an off-screen window so SwiftUI materialises its AppKit controls.
    private func host(_ store: PreferencesStore) -> NSHostingView<AnyView> {
        let view = RecordStartView(sizeLabel: "100 × 50", store: store, onStart: {}, onCancel: {})
        let host = NSHostingView(rootView: AnyView(view.frame(width: RecordStartView.size.width,
                                                              height: RecordStartView.size.height)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: RecordStartView.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.window = window
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func fpsPopup(in host: NSView) -> NSPopUpButton? {
        allSubviews(of: host).compactMap { $0 as? NSPopUpButton }.first
    }

    /// SwiftUI backs a .checkbox Toggle with a real NSButton; Start and Cancel are
    /// SwiftUI-hosted buttons, so once the fps popup (an NSPopUpButton, itself an
    /// NSButton subclass) is excluded the checkbox is the only NSButton.
    private func cursorCheckbox(in host: NSView) -> NSButton? {
        allSubviews(of: host).compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }.first
    }

    private func spin(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testFrameRatePickerAndCursorToggleShowTheStoredPreferences() {
        let store = makeStore()
        store.preferences.gifFPS = 10
        store.preferences.showCursorInRecording = false
        let host = host(store)
        let classes = allSubviews(of: host).map { String(describing: type(of: $0)) }
        let popup = fpsPopup(in: host)
        XCTAssertNotNil(popup, "expected an fps popup; found \(classes)")
        XCTAssertEqual(popup?.titleOfSelectedItem, "10 fps")
        let checkbox = cursorCheckbox(in: host)
        XCTAssertNotNil(checkbox, "expected a cursor checkbox; found \(classes)")
        XCTAssertEqual(checkbox?.state, .off)
    }

    func testControlsFollowChangesToTheStore() {
        let store = makeStore()
        store.preferences.gifFPS = 15
        store.preferences.showCursorInRecording = true
        let host = host(store)
        XCTAssertEqual(fpsPopup(in: host)?.titleOfSelectedItem, "15 fps")
        XCTAssertEqual(cursorCheckbox(in: host)?.state, .on)

        store.preferences.gifFPS = 30
        store.preferences.showCursorInRecording = false
        spin()
        XCTAssertEqual(fpsPopup(in: host)?.titleOfSelectedItem, "30 fps",
                       "the bar must be bound to the same preference Settings → Recording edits")
        XCTAssertEqual(cursorCheckbox(in: host)?.state, .off)
    }

    /// Measures the bar's natural one-line size, not a size forced on it: a
    /// forced size hides overflow by wrapping labels ("Cur-sor", a two-line size).
    func testControlsFitInsideThePanelOnOneLine() {
        let view = RecordStartView(sizeLabel: SelectionGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 8888, height: 8888), scale: 1),
                                   store: makeStore(), onStart: {}, onCancel: {})
        let fitting = NSHostingView(rootView: view).fittingSize
        XCTAssertLessThanOrEqual(fitting.width, RecordStartView.size.width)
        XCTAssertLessThanOrEqual(fitting.height, RecordStartView.size.height)
    }
}
