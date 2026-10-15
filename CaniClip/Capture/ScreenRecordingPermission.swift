import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt the first time; returns the current state.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns true when capture may proceed. Otherwise requests access, explains
    /// the relaunch requirement, and offers to open System Settings.
    @MainActor
    static func ensureGranted() -> Bool {
        if isGranted { return true }
        if request() { return true }
        presentRelaunchAlert()
        return false
    }

    /// Explains that access must be granted in System Settings and the app relaunched.
    @MainActor
    static func presentRelaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "CaniClip needs Screen Recording access"
        alert.informativeText = "Turn on CaniClip under System Settings → Privacy & Security → Screen Recording, then quit and reopen CaniClip. macOS applies this permission only after a relaunch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }
}
