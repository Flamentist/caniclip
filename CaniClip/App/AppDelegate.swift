import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var coordinator: CaptureCoordinator?
    private var hotkeys: HotkeyController?
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install()

        var coordinatorRef: CaptureCoordinator?
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: { coordinatorRef?.handle(.areaScreenshot) },
            captureFullScreen: { coordinatorRef?.handle(.fullScreenScreenshot) },
            recordArea: { coordinatorRef?.handle(.areaRecording) },
            openSettings: { coordinatorRef?.openSettings() },
            quit: { NSApp.terminate(nil) }
        ))
        let coordinator = CaptureCoordinator(appState: appState, preferences: .shared, statusItem: status)
        coordinatorRef = coordinator
        status.onStopRecordingClicked = { coordinator.stopRecording() }
        status.menuItem(for: .captureArea)?.setShortcut(for: .captureArea)
        status.menuItem(for: .captureFullScreen)?.setShortcut(for: .captureFullScreen)
        status.menuItem(for: .recordArea)?.setShortcut(for: .recordArea)

        hotkeys = HotkeyController { kind in coordinator.handle(kind) }
        statusItem = status
        self.coordinator = coordinator

        if !ScreenRecordingPermission.isGranted {
            ScreenRecordingPermission.request()
        }
    }
}
