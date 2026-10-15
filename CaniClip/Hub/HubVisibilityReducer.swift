import Foundation

/// Decides when the hub window hides for a capture and when it comes back.
/// Pure so the cancelled-selection path can be tested without windows.
struct HubVisibilityReducer {
    enum Action: Equatable { case hide, restore }

    private(set) var hiddenForCapture = false

    mutating func action(for mode: AppMode, hubVisible: Bool) -> Action? {
        switch mode {
        case .selecting, .recording, .finishing:
            guard hubVisible, !hiddenForCapture else { return nil }
            hiddenForCapture = true
            return .hide
        case .idle, .editing:
            guard hiddenForCapture else { return nil }
            hiddenForCapture = false
            return .restore
        }
    }
}
