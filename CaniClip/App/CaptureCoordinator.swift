import AppKit

/// Routes hotkey and menu requests through AppState and runs the capture flows.
@MainActor
final class CaptureCoordinator {
    let appState: AppState
    let preferences: PreferencesStore
    let statusItem: StatusItemController
    let overlay = SelectionOverlayController()
    let capturer = ScreenCapturer()

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

    // MARK: Selection

    func beginSelection(_ kind: CaptureKind) {
        guard ScreenRecordingPermission.ensureGranted() else { return }
        appState.transition(to: .selecting(kind))
        overlay.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case .cancelled:
                self.appState.transition(to: .idle)
            case .selected(let globalRect, let screen):
                switch kind {
                case .areaScreenshot:
                    Task { await self.captureScreenshot(globalRect: globalRect, screen: screen) }
                case .areaRecording:
                    self.prepareRecording(globalRect: globalRect, screen: screen)
                case .fullScreenScreenshot:
                    self.appState.transition(to: .idle)
                }
            }
        }
    }

    func captureFullScreen() {
        guard ScreenRecordingPermission.ensureGranted() else { return }
        guard let screen = CaptureGeometry.screen(containing: NSEvent.mouseLocation, screens: NSScreen.screens) else { return }
        appState.transition(to: .selecting(.fullScreenScreenshot))
        Task { await captureScreenshot(globalRect: nil, screen: screen) }
    }

    private func captureScreenshot(globalRect: CGRect?, screen: NSScreen) async {
        do {
            let image = try await capturer.capture(globalRect: globalRect, on: screen)
            deliverScreenshot(image)
        } catch {
            appState.transition(to: .idle)
            ErrorPresenter.present(error, title: "Screenshot failed")
        }
    }

    // MARK: Delivery

    func deliverScreenshot(_ image: CGImage) {
        switch preferences.preferences.afterCapture {
        case .openEditor:
            openEditor(image)
        case .copyToClipboard:
            ImageExporter.copyToClipboard(image)
            playCaptureSound()
            appState.transition(to: .idle)
        case .saveToFolder:
            do {
                _ = try saveScreenshot(image)
                playCaptureSound()
            } catch {
                ErrorPresenter.present(error, title: "Could not save screenshot")
            }
            appState.transition(to: .idle)
        }
    }

    @discardableResult
    func saveScreenshot(_ image: CGImage) throws -> URL {
        let url = FileNamer.uniqueURL(in: preferences.preferences.saveFolderURL, ext: "png")
        try ImageExporter.writePNG(image, to: url)
        return url
    }

    func openEditor(_ image: CGImage) {
        // Interim behaviour until the editor exists (Task 13): save and copy.
        do {
            let url = try saveScreenshot(image)
            ImageExporter.copyToClipboard(image)
            NSLog("Saved screenshot to \(url.path)")
            playCaptureSound()
        } catch {
            ErrorPresenter.present(error, title: "Could not save screenshot")
        }
        appState.transition(to: .idle)
    }

    private func playCaptureSound() {
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    // MARK: Recording (filled in by Task 15)

    func prepareRecording(globalRect: CGRect, screen: NSScreen) {
        NSLog("prepareRecording(\(globalRect)) on \(screen.localizedName) — implemented in Task 15")
        appState.transition(to: .idle)
    }

    func stopRecording() {
        NSLog("stopRecording — implemented in Task 15")
    }

    func openSettings() {
        NSLog("openSettings — implemented in Task 17")
    }
}
