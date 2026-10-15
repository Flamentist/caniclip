import AppKit
import ScreenCaptureKit

/// Runs one area recording at a time: SCStream → StreamOutput → GifRecordingSink → file.
@MainActor
final class RecordingController: NSObject, SCStreamDelegate {
    struct Output {
        let url: URL
        let summary: GifSummary
    }

    enum RecordingError: LocalizedError {
        case alreadyRecording
        case streamStopped(Error)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "A recording is already in progress."
            case .streamStopped(let e): return "The screen recording stopped: \(e.localizedDescription)"
            }
        }
    }

    private(set) var isRecording = false
    var onFinished: ((Result<Output, Error>) -> Void)?

    private let preferences: PreferencesStore
    private var stream: SCStream?
    private var output: StreamOutput?
    private var sink: GifRecordingSink?
    private var frameWindow: RegionFrameWindow?
    private var hudPanel: FloatingPanel?
    private let hudModel = RecordingHUDModel()
    private var timer: Timer?
    private var startedAt: Date?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func start(globalRect: CGRect, screen: NSScreen) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }
        let prefs = preferences.preferences

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = ScreenCapturer.filterExcludingSelf(display: display, content: content)
        let geometry = DisplayGeometry(frame: screen.frame, scale: screen.backingScaleFactor)
        let source = CaptureGeometry.sourceRect(globalRect: globalRect, display: geometry)
        let px = CaptureGeometry.pixelSize(pointSize: source.size, scale: geometry.scale)

        let config = SCStreamConfiguration()
        config.sourceRect = source
        config.width = px.width
        config.height = px.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, prefs.gifFPS)))
        config.showsCursor = prefs.showCursorInRecording
        config.queueDepth = 5
        config.capturesAudio = false

        let settings = GifSettings(maxWidth: prefs.gifMaxWidth.maxWidthValue, maxHeight: nil,
                                   quality: UInt8(min(100, max(1, prefs.gifQuality))), fast: false, repeat: 0)
        let sink = try GifRecordingSink(settings: settings)
        let output = StreamOutput(sink: sink)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.sink = sink
        isRecording = true
        startedAt = Date()
        showChrome(globalRect: globalRect, screen: screen, maxSeconds: prefs.maxRecordingSeconds)
    }

    func stop() {
        guard isRecording, let stream, let sink else { return }
        isRecording = false
        hideChrome()
        let folder = preferences.preferences.saveFolderURL
        Task { [weak self] in
            do {
                try await stream.stopCapture()
            } catch {
                // Stopping after the stream already ended is not a failure for the GIF.
            }
            let url = FileNamer.uniqueURL(in: folder, ext: "gif")
            do {
                let summary = try await sink.finish(to: url)
                self?.onFinished?(.success(Output(url: url, summary: summary)))
            } catch {
                self?.onFinished?(.failure(error))
            }
            self?.stream = nil
            self?.output = nil
            self?.sink = nil
        }
    }

    // MARK: SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard isRecording else { return }
            isRecording = false
            hideChrome()
            sink?.cancel()
            self.stream = nil
            output = nil
            sink = nil
            onFinished?(.failure(RecordingError.streamStopped(error)))
        }
    }

    // MARK: Chrome

    private func showChrome(globalRect: CGRect, screen: NSScreen, maxSeconds: Int) {
        let frame = RegionFrameWindow(globalRect: globalRect)
        frame.setStyle(.recording)
        frame.orderFrontRegardless()
        frameWindow = frame

        hudModel.elapsed = 0
        let hud = FloatingPanel(content: RecordingHUDView(model: hudModel) { [weak self] in self?.stop() },
                                size: RecordingHUDView.size)
        let origin = PanelPlacement.origin(panelSize: RecordingHUDView.size, nearRegion: globalRect,
                                           visibleFrame: screen.visibleFrame, gap: 12)
        hud.show(at: origin)
        hudPanel = hud

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.hudModel.elapsed = Date().timeIntervalSince(startedAt)
                if self.hudModel.elapsed >= Double(maxSeconds) { self.stop() }
            }
        }
    }

    private func hideChrome() {
        timer?.invalidate()
        timer = nil
        hudPanel?.orderOut(nil)
        hudPanel = nil
        frameWindow?.orderOut(nil)
        frameWindow = nil
        startedAt = nil
    }
}
