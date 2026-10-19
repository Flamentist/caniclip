import AppKit
import UniformTypeIdentifiers
import Combine

/// Routes hotkey and menu requests through AppState and runs the capture flows.
@MainActor
final class CaptureCoordinator {
    let appState: AppState
    let preferences: PreferencesStore
    let statusItem: StatusItemController
    let library: CaptureLibrary
    let overlay = SelectionOverlayController()
    let capturer = ScreenCapturer()
    private var reportedLibraryFailure = false
    private var hubVisibility = HubVisibilityReducer()
    private var modeObserver: AnyCancellable?
    private var dockObserver: AnyCancellable?
    private var hubOpen = false
    private lazy var hub: HubWindowController = {
        let controller = HubWindowController(viewModel: HubViewModel(library: library), actions: hubActions())
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.hubVisibility.hubClosed()
            self.hubOpen = false
            self.applyActivationPolicy()
        }
        return controller
    }()
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

    init(appState: AppState, preferences: PreferencesStore, statusItem: StatusItemController,
         library: CaptureLibrary? = nil) {
        self.appState = appState
        self.preferences = preferences
        self.statusItem = statusItem
        let library = library ?? CaptureLibrary.shared
        self.library = library
        pruneHistory()
        dockObserver = preferences.$preferences
            .map(\.showInDock)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // @Published emits before the value is stored; apply on the next run-loop turn.
                DispatchQueue.main.async { self?.applyActivationPolicy() }
            }
        modeObserver = appState.$mode.sink { [weak self] mode in
            guard let self else { return }
            switch self.hubVisibility.action(for: mode, hubVisible: self.hub.isShowing) {
            case .hide: self.hub.hideForCapture()
            case .restore: self.hub.restoreAfterCapture()
            case nil: break
            }
        }
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
        // Recording takes a dragged area, or a click for the whole screen.
        overlay.begin(clickSelectsScreen: kind == .areaRecording) { [weak self] result in
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

    /// Delivers first and records afterwards, so history bookkeeping never
    /// delays the clipboard, the save or the editor.
    func deliverScreenshot(_ image: CGImage) {
        switch preferences.preferences.afterCapture {
        case .openEditor:
            let controller = openEditor(image)
            attachRecord(recordScreenshot(image), to: controller)
        case .copyToClipboard:
            ImageExporter.copyToClipboard(image)
            playCaptureSound()
            recordScreenshot(image)
            appState.transition(to: .idle)
        case .saveToFolder:
            var png: Data?
            do {
                let encoded = try ImageExporter.pngData(from: image)
                png = encoded
                let url = try saveScreenshot(pngData: encoded)
                playCaptureSound()
                if let recordID = recordScreenshot(image, pngData: encoded) {
                    do { try library.markSaved(id: recordID, to: url, annotated: nil) } catch { reportLibraryFailure(error) }
                }
                appState.transition(to: .idle)
            } catch {
                // Never drop the capture: explain, then hand it to the editor,
                // whose Save As… lets the user pick a writable location.
                ErrorPresenter.present(error, title: "Could not save screenshot")
                let controller = openEditor(image)
                attachRecord(recordScreenshot(image, pngData: png), to: controller)
            }
        }
    }

    // MARK: History

    @discardableResult
    private func recordScreenshot(_ image: CGImage, pngData: Data? = nil, title: String? = nil,
                                  styleScale: CGFloat? = nil) -> UUID? {
        do {
            let id = try library.addScreenshot(image, pngData: pngData, title: title, styleScale: styleScale.map(Double.init)).id
            pruneHistory()
            return id
        } catch {
            reportLibraryFailure(error)
            return nil
        }
    }

    /// Retention is enforced at launch and after every addition.
    private func pruneHistory() {
        do {
            try library.prune(olderThan: preferences.preferences.historyRetentionDays)
        } catch {
            reportLibraryFailure(error)
        }
    }

    private func recordGif(url: URL, summary: GifSummary?) {
        do {
            try library.addGif(url: url, summary: summary)
            pruneHistory()
        } catch {
            reportLibraryFailure(error)
        }
    }

    /// History is a convenience; its failures are shown once and never block a capture.
    private func reportLibraryFailure(_ error: Error) {
        NSLog("CaptureLibrary error: %@", error.localizedDescription)
        guard !reportedLibraryFailure else { return }
        reportedLibraryFailure = true
        ErrorPresenter.present(error, title: "History is unavailable")
    }

    @discardableResult
    func saveScreenshot(pngData: Data) throws -> URL {
        let url = FileNamer.uniqueURL(in: preferences.preferences.saveFolderURL, ext: "png")
        try ImageExporter.writePNG(data: pngData, to: url)
        return url
    }

    @discardableResult
    func openEditor(_ image: CGImage, recordID: UUID? = nil, title: String = "Screenshot",
                    scalesStyleToFit: Bool = false, styleScale: CGFloat? = nil,
                    annotations: [Annotation] = []) -> EditorWindowController {
        let controller = EditorWindowController(image: image, preferences: preferences, title: title,
                                                scalesStyleToFit: scalesStyleToFit, styleScale: styleScale,
                                                annotations: annotations)
        attachRecord(recordID, to: controller)
        controller.onClose = { [weak self, weak controller] in
            guard let self else { return }
            // Whatever the user chose about saving a file, history keeps their edits.
            if let controller { self.storeEdits(of: controller) }
            self.editors.removeAll { $0 === controller }
            if self.editors.isEmpty, self.appState.mode == .editing {
                self.appState.transition(to: .idle)
            }
        }
        editors.append(controller)
        // An editor opened mid-capture (say, a file dropped on the Dock while
        // recording) must not take over: the record shortcut still has to stop it.
        if appState.mode == .idle || appState.mode == .editing {
            appState.transition(to: .editing)
        }
        controller.present()
        return controller
    }

    // MARK: Import

    /// Opens an image from outside CaniClip in the editor and adds it to history.
    func openImported(_ imported: ImportedImage) {
        let controller = openEditor(imported.image, title: imported.title, scalesStyleToFit: true)
        let id = recordScreenshot(imported.image, title: imported.title, styleScale: controller.editorDocument.styleScale)
        attachRecord(id, to: controller)
    }

    /// Opens the first of `urls`; the rest are ignored.
    func openFiles(_ urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            guard ImageImporter.isImageFile(url) else { throw ImportError.unreadableFile }
            openImported(try ImageImporter.image(contentsOf: url))
        } catch {
            reportImportFailure(error, title: "Could not open")
        }
    }

    /// Image data dropped on the hub, such as an image dragged out of a browser.
    func openImageData(_ data: Data) {
        do {
            openImported(try ImageImporter.image(from: data, title: "Dropped Image"))
        } catch {
            reportImportFailure(error, title: "Could not open")
        }
    }

    func pasteImage(from pasteboard: NSPasteboard = .general) {
        do {
            openImported(try ImageImporter.image(from: pasteboard))
        } catch {
            reportImportFailure(error, title: "Could not paste")
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        openFiles(panel.urls)
    }

    private func reportImportFailure(_ error: Error, title: String) {
        NSSound.beep()
        ErrorPresenter.present(error, title: title)
    }

    /// Links an editor's saves to its history record. Safe to call after the
    /// editor is already on screen: `onSaved` only fires on a later user save.
    private func attachRecord(_ recordID: UUID?, to controller: EditorWindowController) {
        controller.recordID = recordID
        controller.onSaved = { [weak self, weak controller] url, annotated in
            guard let self, let recordID else { return }
            do { try self.library.markSaved(id: recordID, to: url, annotated: annotated) } catch { self.reportLibraryFailure(error) }
            if let controller { self.storeEdits(of: controller) }
        }
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
            recordGif(url: output.url, summary: output.summary)
            presentRecordingResult(output)
        case .failure(let error):
            if case CoreError.OutputUnwritable(_, let tempPath) = error {
                // The GIF is complete but the chosen folder refused it: show the
                // user where it is instead of losing a whole recording.
                let kept = URL(fileURLWithPath: tempPath)
                recordGif(url: kept, summary: nil)
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

    // MARK: Hub

    func openHub() {
        switch appState.mode {
        case .selecting, .recording, .finishing: return
        case .idle, .editing: break
        }
        hubOpen = true
        applyActivationPolicy()
        hub.present()
    }

    /// Dock presence follows the "Show in Dock" setting, plus the hub while it is open.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(ActivationPolicyRule.policy(openHubWindows: hubOpen ? 1 : 0,
                                                              showInDock: preferences.preferences.showInDock))
    }

    private func hubActions() -> HubActions {
        HubActions(
            captureArea: { [weak self] in self?.handle(.areaScreenshot) },
            captureFullScreen: { [weak self] in self?.handle(.fullScreenScreenshot) },
            recordArea: { [weak self] in self?.handle(.areaRecording) },
            openSettings: { [weak self] in self?.openSettings() },
            openSaveFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.preferences.preferences.saveFolderURL)
            },
            openRecord: { [weak self] in self?.openRecord($0) },
            copyRecord: { [weak self] in self?.copyRecord($0) },
            revealRecord: { [weak self] in
                guard let self, let url = self.library.bestFileURL(for: $0) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            deleteRecord: { [weak self] in self?.deleteRecord($0) },
            openFile: { [weak self] in self?.showOpenPanel() },
            pasteImage: { [weak self] in self?.pasteImage() },
            openURLs: { [weak self] in self?.openFiles($0) },
            openImageData: { [weak self] in self?.openImageData($0) }
        )
    }

    /// Keeps an editor's annotations with its history entry, and its thumbnail current.
    private func storeEdits(of controller: EditorWindowController) {
        guard let id = controller.recordID, library.records.contains(where: { $0.id == id }) else { return }
        let document = controller.editorDocument
        do {
            try library.saveEdits(document.annotations, for: id, rendered: document.rasterize())
        } catch {
            reportLibraryFailure(error)
        }
    }

    func openRecord(_ record: CaptureRecord) {
        if let open = editors.first(where: { $0.recordID == record.id }) {
            open.present()
            return
        }
        guard let url = library.bestFileURL(for: record) else { return }
        switch record.kind {
        case .screenshot:
            // The original capture plus its stored edits, still editable. Without the
            // original only the saved (flattened) file is left, so edits can't apply.
            if let original = library.image(for: record.id) {
                let controller = openEditor(original, recordID: record.id, title: record.title ?? "Screenshot",
                                            styleScale: record.styleScale.map { CGFloat($0) },
                                            annotations: library.edits(for: record.id))
                if let path = record.savedPath, FileManager.default.fileExists(atPath: path) {
                    controller.editorDocument.markSaved(to: URL(fileURLWithPath: path))
                }
                return
            }
            guard let image = ThumbnailMaker.firstFrame(ofImageAt: url) else { return }
            openEditor(image, recordID: record.id)
        case .gif:
            NSWorkspace.shared.open(url)
        }
    }

    private func copyRecord(_ record: CaptureRecord) {
        guard let url = library.bestFileURL(for: record) else { return }
        switch record.kind {
        case .screenshot:
            if let image = ThumbnailMaker.firstFrame(ofImageAt: url) { ImageExporter.copyToClipboard(image) }
        case .gif:
            ImageExporter.copyFileToClipboard(url)
        }
    }

    private func deleteRecord(_ record: CaptureRecord) {
        let alert = NSAlert()
        alert.messageText = "Remove this capture from history?"
        alert.informativeText = "Only the history entry and CaniClip's own copy are removed. Files in your save folder are not affected."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try library.delete(id: record.id) } catch { ErrorPresenter.present(error, title: "Could not remove from history") }
    }

    func openSettings() {
        settingsWindow.present()
    }

}
