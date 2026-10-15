import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: PreferencesStore) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "CaniClip Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
