import AppKit

/// Full-screen dimming view that lets the user drag out a rectangle.
/// Coordinates are window-local (AppKit, bottom-left origin); the owner converts to global.
final class SelectionView: NSView {
    var onFinished: ((CGRect?) -> Void)?   // nil = cancelled; rect is window-local
    /// When true, a click without a drag selects this whole screen instead of cancelling.
    var clickSelectsScreen = false { didSet { needsDisplay = true } }

    private let scale: CGFloat
    private var anchor: CGPoint?
    private var current: CGPoint?
    private var constrainSquare = false
    private var spaceHeld = false
    private var lastDrag: CGPoint?
    private var finished = false

    init(frame: CGRect, scale: CGFloat) {
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The hotkey fires while another app is frontmost; the first click must start
    /// the drag rather than be swallowed as the activating click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        return SelectionGeometry.rect(from: anchor, to: current, constrainSquare: constrainSquare)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        guard let rect = selectionRect else {
            if clickSelectsScreen { drawHint("Drag to record an area  ·  Click to record the full screen", in: ctx) }
            return
        }
        ctx.clear(rect)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        drawSizeLabel(for: rect, in: ctx)
    }

    private func drawSizeLabel(for rect: CGRect, in ctx: CGContext) {
        let text = SelectionGeometry.sizeLabel(for: rect, scale: scale) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - pad * 2 - 4)
        if origin.y < 0 { origin.y = rect.maxY + 4 }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + pad * 2, height: size.height + pad * 2)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let path = CGPath(roundedRect: box, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad), withAttributes: attrs)
    }

    private func drawHint(_ hint: String, in ctx: CGContext) {
        let text = hint as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad = CGSize(width: 16, height: 10)
        let box = CGRect(x: bounds.midX - size.width / 2 - pad.width, y: bounds.midY - size.height / 2 - pad.height,
                         width: size.width + pad.width * 2, height: size.height + pad.height * 2)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: box.height / 2, cornerHeight: box.height / 2, transform: nil))
        ctx.fillPath()
        text.draw(at: CGPoint(x: box.minX + pad.width, y: box.minY + pad.height), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        anchor = p
        current = p
        lastDrag = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spaceHeld, let last = lastDrag, let a = anchor, let c = current {
            let dx = p.x - last.x, dy = p.y - last.y
            anchor = CGPoint(x: a.x + dx, y: a.y + dy)
            current = CGPoint(x: c.x + dx, y: c.y + dy)
        } else {
            current = p
        }
        lastDrag = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect else { return finish(nil) }
        guard SelectionGeometry.isUsable(rect) else { return finish(clickSelectsScreen ? bounds : nil) }
        finish(rect.intersection(bounds))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: finish(nil)                 // Escape
        case 49: spaceHeld = true            // Space
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    override func flagsChanged(with event: NSEvent) {
        constrainSquare = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    private func finish(_ rect: CGRect?) {
        guard !finished else { return }
        finished = true
        onFinished?(rect)
    }
}
