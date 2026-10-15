import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The display to capture could not be found."
        }
    }
}

@MainActor
final class ScreenCapturer {
    /// Captures `globalRect` (AppKit global points; nil = whole screen) on `screen`
    /// at native pixel scale. CaniClip's own windows are excluded so overlays and
    /// panels never appear in the result.
    func capture(globalRect: CGRect?, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = Self.filterExcludingSelf(display: display, content: content)
        let geometry = DisplayGeometry(frame: screen.frame, scale: screen.backingScaleFactor)
        let source = CaptureGeometry.sourceRect(globalRect: globalRect ?? screen.frame, display: geometry)
        let px = CaptureGeometry.pixelSize(pointSize: source.size, scale: geometry.scale)

        let config = SCStreamConfiguration()
        config.sourceRect = source
        config.width = px.width
        config.height = px.height
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Content filter for `display` that hides every window belonging to this process.
    static func filterExcludingSelf(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
    }
}
