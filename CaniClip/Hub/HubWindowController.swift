import AppKit
import SwiftUI

@MainActor
final class HubWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(viewModel: HubViewModel, actions: HubActions) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "CaniClip"
        window.minSize = CGSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CaniClipHub")
        window.contentView = NSHostingView(rootView: HubView(viewModel: viewModel, actions: actions))
        if !window.setFrameUsingName("CaniClipHub") { window.center() }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isShowing: Bool { window?.isVisible ?? false }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Hides without closing, so the window frame and policy are untouched.
    func hideForCapture() {
        window?.orderOut(nil)
    }

    func restoreAfterCapture() {
        window?.orderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
