import AppKit
import SwiftUI

/// Hosts the hub and turns ⌘V into "paste an image into the editor"; the hub
/// has no text fields, so nothing else wants it.
final class HubHostingView: NSHostingView<HubView> {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            rootView.actions.pasteImage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class HubWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(viewModel: HubViewModel, actions: HubActions) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "CaniClip"
        // The content draws its own header, so the system title bar fades into it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = CGSize(width: 560, height: 380)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CaniClipHub")
        window.contentView = HubHostingView(rootView: HubView(viewModel: viewModel, actions: actions))
        if !window.setFrameUsingName("CaniClipHub") { window.center() }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Visible and not sitting in the Dock as a miniaturised window.
    var isShowing: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
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
