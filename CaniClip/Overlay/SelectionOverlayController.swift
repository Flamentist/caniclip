import AppKit

enum SelectionResult {
    case cancelled
    case selected(globalRect: CGRect, screen: NSScreen)
}

/// Shows one dimming overlay per screen and reports the dragged rectangle in
/// global AppKit coordinates. Overlays are closed before `completion` runs.
@MainActor
final class SelectionOverlayController {
    private var windows: [SelectionOverlayWindow] = []
    private var completion: ((SelectionResult) -> Void)?

    func begin(completion: @escaping (SelectionResult) -> Void) {
        cancel()
        self.completion = completion
        windows = NSScreen.screens.map { screen in
            let window = SelectionOverlayWindow(screen: screen)
            window.selectionView.onFinished = { [weak self, weak window] localRect in
                guard let self else { return }
                guard let localRect, let window else { return self.finish(.cancelled) }
                let global = localRect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
                self.finish(.selected(globalRect: global, screen: window.screenTarget))
            }
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        keyWindow?.makeFirstResponder(keyWindow?.selectionView)
        NSCursor.crosshair.set()
    }

    /// Dismisses the overlays without reporting a result.
    func cancel() {
        closeWindows()
        completion = nil
    }

    private func finish(_ result: SelectionResult) {
        let done = completion
        completion = nil
        closeWindows()
        done?(result)
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
    }
}
