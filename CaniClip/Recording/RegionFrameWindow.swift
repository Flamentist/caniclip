import AppKit

enum RegionFrameStyle {
    case armed, recording
}

/// Click-through border drawn around the region being recorded. Excluded from
/// capture along with every other CaniClip window.
final class RegionFrameWindow: NSWindow {
    private let borderView: BorderView

    init(globalRect: CGRect) {
        let inset: CGFloat = 3
        let frame = globalRect.insetBy(dx: -inset, dy: -inset)
        borderView = BorderView(frame: CGRect(origin: .zero, size: frame.size), lineWidth: 2)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = borderView
    }

    func setStyle(_ style: RegionFrameStyle) {
        borderView.color = style == .recording ? .systemRed : .white
    }

    private final class BorderView: NSView {
        var color: NSColor = .white { didSet { needsDisplay = true } }
        private let lineWidth: CGFloat

        init(frame: CGRect, lineWidth: CGFloat) {
            self.lineWidth = lineWidth
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        }
    }
}
