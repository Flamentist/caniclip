import AppKit

final class SelectionOverlayWindow: NSWindow {
    let screenTarget: NSScreen
    let selectionView: SelectionView

    init(screen: NSScreen) {
        screenTarget = screen
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
        initialFirstResponder = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
