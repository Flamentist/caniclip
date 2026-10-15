import Foundation
import KeyboardShortcuts

@MainActor
final class HotkeyController {
    init(handler: @escaping @MainActor (CaptureKind) -> Void) {
        KeyboardShortcuts.onKeyUp(for: .captureArea) { handler(.areaScreenshot) }
        KeyboardShortcuts.onKeyUp(for: .recordArea) { handler(.areaRecording) }
        KeyboardShortcuts.onKeyUp(for: .captureFullScreen) { handler(.fullScreenScreenshot) }
    }
}
