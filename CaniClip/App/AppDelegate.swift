import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController(actions: StatusMenuActions(
            captureArea: { NSLog("Capture Area requested") },
            captureFullScreen: { NSLog("Capture Full Screen requested") },
            recordArea: { NSLog("Record Area requested") },
            openSettings: { NSLog("Settings requested") },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
