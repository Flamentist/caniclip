import AppKit

/// Routes hotkey and menu requests through AppState and runs the capture flows.
@MainActor
final class CaptureCoordinator {
    let appState: AppState
    let preferences: PreferencesStore
    let statusItem: StatusItemController

    init(appState: AppState, preferences: PreferencesStore, statusItem: StatusItemController) {
        self.appState = appState
        self.preferences = preferences
        self.statusItem = statusItem
    }

    func handle(_ kind: CaptureKind) {
        switch appState.action(for: kind) {
        case .startSelection(let k): beginSelection(k)
        case .captureFullScreenNow: captureFullScreen()
        case .stopRecording: stopRecording()
        case .ignore: break
        }
    }

    func beginSelection(_ kind: CaptureKind) {
        NSLog("beginSelection(\(kind)) — implemented in Task 10")
    }

    func captureFullScreen() {
        NSLog("captureFullScreen — implemented in Task 10")
    }

    func stopRecording() {
        NSLog("stopRecording — implemented in Task 15")
    }

    func openSettings() {
        NSLog("openSettings — implemented in Task 17")
    }
}
