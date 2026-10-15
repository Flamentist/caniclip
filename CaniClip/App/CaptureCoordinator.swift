import AppKit

/// Routes hotkey and menu requests through AppState and runs the capture flows.
@MainActor
final class CaptureCoordinator {
    let appState: AppState
    let preferences: PreferencesStore
    let statusItem: StatusItemController
    let overlay = SelectionOverlayController()
    let capturer = ScreenCapturer()
    private var editors: [EditorWindowController] = []
    private lazy var recorder: RecordingController = {
        let r = RecordingController(preferences: preferences)
        r.onStopping = { [weak self] in self?.appState.transition(to: .finishing) }
        r.onFinished = { [weak self] result in self?.recordingFinished(result) }
        return r
    }()
    private var armedFrame: RegionFrameWindow?
    private var startPanel: FloatingPanel?
    private lazy var quickAccess = QuickAccessPresenter(statusItem: statusItem)
    private lazy var settingsWindow = SettingsWindowController(store: preferences)

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
            presentCaptureFailure(error, title: "Screenshot failed")
        }
    }

    /// Permission problems get the relaunch explanation; everything else a plain alert.
    private func presentCaptureFailure(_ error: Error, title: String) {
        if CaptureFailure.isPermissionDenied(error) {
            ScreenRecordingPermission.presentRelaunchAlert()
        } else {
            ErrorPresenter.present(error, title: title)
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
                appState.transition(to: .idle)
            } catch {
                // Never drop the capture: explain, then hand it to the editor,
                // whose Save As… lets the user pick a writable location.
                ErrorPresenter.present(error, title: "Could not save screenshot")
                openEditor(image)
            }
        }
    }

    @discardableResult
    func saveScreenshot(_ image: CGImage) throws -> URL {
        let url = FileNamer.uniqueURL(in: preferences.preferences.saveFolderURL, ext: "png")
        try ImageExporter.writePNG(image, to: url)
        return url
    }

    func openEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image, preferences: preferences)
        controller.onClose = { [weak self, weak controller] in
            guard let self else { return }
            self.editors.removeAll { $0 === controller }
            if self.editors.isEmpty, self.appState.mode == .editing {
                self.appState.transition(to: .idle)
            }
        }
        editors.append(controller)
        appState.transition(to: .editing)
        controller.present()
    }

    var openEditorCount: Int { editors.count }
    var editorsForTesting: [EditorWindowController] { editors }

    /// Asks every editor with unsaved annotations; false if any of them cancels.
    func editorsAllowTermination() -> Bool {
        for editor in editors where editor.editorDocument.isDirty {
            if !editor.confirmClose() { return false }
        }
        return true
    }

    func closeAllEditorsForTesting() {
        for editor in editors {
            editor.window?.delegate = nil
            editor.close()
        }
        editors = []
        appState.transition(to: .idle)
    }

    private func playCaptureSound() {
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    // MARK: Recording

    func prepareRecording(globalRect: CGRect, screen: NSScreen) {
        let frame = RegionFrameWindow(globalRect: globalRect)
        frame.setStyle(.armed)
        frame.orderFrontRegardless()
        armedFrame = frame

        let label = SelectionGeometry.sizeLabel(for: globalRect, scale: screen.backingScaleFactor)
        let panel = FloatingPanel(content: RecordStartView(
            sizeLabel: label,
            store: preferences,
            onStart: { [weak self] in
                self?.dismissArmedChrome()
                Task { await self?.startRecording(globalRect: globalRect, screen: screen) }
            },
            onCancel: { [weak self] in
                self?.dismissArmedChrome()
                self?.appState.transition(to: .idle)
            }
        ), size: RecordStartView.size)
        let origin = PanelPlacement.origin(panelSize: RecordStartView.size, nearRegion: globalRect,
                                           visibleFrame: screen.visibleFrame, gap: 12)
        NSApp.activate(ignoringOtherApps: true)
        panel.show(at: origin)
        startPanel = panel
    }

    private func dismissArmedChrome() {
        startPanel?.orderOut(nil)
        startPanel = nil
        armedFrame?.orderOut(nil)
        armedFrame = nil
    }

    private func startRecording(globalRect: CGRect, screen: NSScreen) async {
        do {
            try await recorder.start(globalRect: globalRect, screen: screen)
            appState.transition(to: .recording)
            statusItem.setRecording(true)
        } catch {
            appState.transition(to: .idle)
            presentCaptureFailure(error, title: "Could not start recording")
        }
    }

    func stopRecording() {
        recorder.stop()
    }

    private func recordingFinished(_ result: Result<RecordingController.Output, Error>) {
        statusItem.setRecording(false)
        appState.transition(to: .idle)
        switch result {
        case .success(let output):
            ImageExporter.copyFileToClipboard(output.url)
            NSSound(named: NSSound.Name("Pop"))?.play()
            presentRecordingResult(output)
        case .failure(let error):
            if case CoreError.OutputUnwritable(_, let tempPath) = error {
                // The GIF is complete but the chosen folder refused it: show the
                // user where it is instead of losing a whole recording.
                let kept = URL(fileURLWithPath: tempPath)
                ErrorPresenter.present(error, title: "Could not save the GIF to your folder")
                ImageExporter.copyFileToClipboard(kept)
                NSWorkspace.shared.activateFileViewerSelecting([kept])
            } else {
                presentCaptureFailure(error, title: "Recording failed")
            }
        }
    }

    func presentRecordingResult(_ output: RecordingController.Output) {
        quickAccess.show(output: output)
    }

    func openSettings() {
        settingsWindow.present()
    }

}
