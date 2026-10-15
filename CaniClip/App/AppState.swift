import Foundation
import Combine

enum CaptureKind: Equatable {
    case areaScreenshot, fullScreenScreenshot, areaRecording
}

enum AppMode: Equatable {
    case idle
    case selecting(CaptureKind)
    case editing
    case recording
    /// Recording stopped; the GIF is still being written.
    case finishing
}

enum HotkeyAction: Equatable {
    case startSelection(CaptureKind)
    case captureFullScreenNow
    case stopRecording
    case ignore
}

/// The single source of truth for what the app is doing. Hotkeys and menu items
/// ask `action(for:)` so both paths behave identically.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var mode: AppMode = .idle

    func action(for kind: CaptureKind) -> HotkeyAction {
        switch (mode, kind) {
        case (.recording, .areaRecording): return .stopRecording
        case (.recording, _): return .ignore
        case (.finishing, _): return .ignore
        case (.selecting, _): return .ignore
        case (_, .fullScreenScreenshot): return .captureFullScreenNow
        case (_, .areaScreenshot), (_, .areaRecording): return .startSelection(kind)
        }
    }

    func transition(to newMode: AppMode) {
        mode = newMode
    }
}
