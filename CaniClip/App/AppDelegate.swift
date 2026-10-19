import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var coordinator: CaptureCoordinator?
    private var hotkeys: HotkeyController?
    private let appState = AppState()
    private let menuActions = MenuActions()
    /// Files opened from Finder or the Dock before launch finished.
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(ActivationPolicyRule.policy(openHubWindows: 0,
                                                              showInDock: PreferencesStore.shared.preferences.showInDock))
        MainMenu.install(actions: menuActions)

        var coordinatorRef: CaptureCoordinator?
        let status = StatusItemController(actions: StatusMenuActions(
            captureArea: { coordinatorRef?.handle(.areaScreenshot) },
            captureFullScreen: { coordinatorRef?.handle(.fullScreenScreenshot) },
            recordArea: { coordinatorRef?.handle(.areaRecording) },
            openHub: { coordinatorRef?.openHub() },
            openSettings: { coordinatorRef?.openSettings() },
            quit: { NSApp.terminate(nil) },
            openImage: { coordinatorRef?.showOpenPanel() },
            pasteImage: { coordinatorRef?.pasteImage() }
        ))
        let coordinator = CaptureCoordinator(appState: appState, preferences: .shared, statusItem: status)
        coordinatorRef = coordinator
        status.onStopRecordingClicked = { coordinator.stopRecording() }
        status.menuItem(for: .captureArea)?.setShortcut(for: .captureArea)
        status.menuItem(for: .captureFullScreen)?.setShortcut(for: .captureFullScreen)
        status.menuItem(for: .recordArea)?.setShortcut(for: .recordArea)

        menuActions.captureArea = { coordinator.handle(.areaScreenshot) }
        menuActions.captureFullScreen = { coordinator.handle(.fullScreenScreenshot) }
        menuActions.recordArea = { coordinator.handle(.areaRecording) }
        menuActions.openHub = { coordinator.openHub() }
        menuActions.openSettings = { coordinator.openSettings() }
        menuActions.openFile = { coordinator.showOpenPanel() }
        menuActions.pasteImage = { coordinator.pasteImage() }

        hotkeys = HotkeyController { kind in coordinator.handle(kind) }
        statusItem = status
        self.coordinator = coordinator
        if !pendingOpenURLs.isEmpty {
            coordinator.openFiles(pendingOpenURLs)
            pendingOpenURLs = []
        }

        if !ScreenRecordingPermission.isGranted {
            ScreenRecordingPermission.request()
        }

        // Test runs host the real app; they must not consume the user's first
        // launch or pop the hub over the test runner.
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        if !isRunningTests,
           PreferencesStore.shared.consumeFirstLaunch() || PreferencesStore.shared.preferences.openHubAtLaunch {
            coordinator.openHub()
        }
    }

    /// Images dropped on the Dock icon or opened with Finder's Open With.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else { return pendingOpenURLs += urls }
        coordinator.openFiles(urls)
    }

    /// Clicking the Dock icon with no windows reopens the hub.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { coordinator?.openHub() }
        return true
    }

    /// ⌘Q must honour the editor's unsaved-changes prompt like the close button does.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        return coordinator.editorsAllowTermination() ? .terminateNow : .terminateCancel
    }
}
