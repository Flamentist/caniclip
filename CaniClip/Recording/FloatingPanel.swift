import AppKit
import SwiftUI

/// Small always-on-top panel hosting a SwiftUI view, used for the record start
/// bar and the recording HUD.
final class FloatingPanel: NSPanel {
    init<Content: View>(content: Content, size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: content
            .frame(width: size.width, height: size.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous)))
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    func show(at origin: CGPoint) {
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
    }
}
