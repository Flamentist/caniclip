import AppKit
import Combine

/// Scales the screenshot to fit, draws annotations on top, and turns mouse input
/// into annotations according to the document's current tool.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let document: EditorDocument
    private var cancellables: Set<AnyCancellable> = []

    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var snapshot: [Annotation] = []
    private var lastDragPoint: CGPoint?
    private var textField: NSTextField?
    private var textOrigin: CGPoint?
    /// A text corner being dragged, with the text as it was when the drag began.
    private var resizing: (corner: Annotation.Corner, original: Annotation)?

    private static let handleSize: CGFloat = 8

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        document.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.needsDisplay = true
                self.styleTextField()
                self.window?.invalidateCursorRects(for: self)
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Geometry

    private var imageSize: CGSize { CGSize(width: document.image.width, height: document.image.height) }

    private var scale: CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / imageSize.width, bounds.height / imageSize.height, 1)
    }

    private var imageRect: CGRect {
        let s = scale
        let size = CGSize(width: imageSize.width * s, height: imageSize.height * s)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let v = convert(event.locationInWindow, from: nil)
        let r = imageRect
        return CGPoint(x: (v.x - r.minX) / scale, y: (v.y - r.minY) / scale)
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x * scale, y: r.minY + p.y * scale)
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch document.tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
        guard let text = selectedText else { return }
        for corner in Annotation.Corner.allCases {
            let c = viewPoint(text.cornerPoint(corner))
            let r = Self.handleSize
            addCursorRect(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                          cursor: .frameResize(position: Self.cursorPosition(corner), directions: .all))
        }
    }

    private static func cursorPosition(_ corner: Annotation.Corner) -> NSCursor.FrameResizePosition {
        // The view is flipped, so "top" in image pixels is the top on screen too.
        switch corner {
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        }
    }

    // MARK: Text handles

    /// Text is the only kind with resize handles.
    private var selectedText: Annotation? { document.selectedText }

    private func handle(at p: CGPoint) -> Annotation.Corner? {
        guard let text = selectedText else { return nil }
        // Small text keeps a middle to grab for moving: handles shrink with its box.
        let box = text.boundingBox
        let reach = min(Self.handleSize / scale, min(box.width, box.height) / 3)
        return Annotation.Corner.allCases.first { corner in
            let c = text.cornerPoint(corner)
            return abs(c.x - p.x) <= reach && abs(c.y - p.y) <= reach
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(document.image, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.clip(to: CGRect(origin: .zero, size: imageSize))
        var all = document.annotations
        if let draft { all.append(draft) }
        AnnotationRenderer.draw(all, in: ctx) { [document] in document.pixelateService.image(for: $0) }
        if let text = selectedText {
            // Text gets an outline on its box with a draggable handle at each corner.
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 / scale)
            ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
            ctx.stroke(text.boundingBox)
            ctx.setLineDash(phase: 0, lengths: [])
            let side = Self.handleSize / scale
            for corner in Annotation.Corner.allCases {
                let c = text.cornerPoint(corner)
                let square = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(square)
                ctx.stroke(square)
            }
        } else if let id = document.selectedID, let sel = document.annotations.first(where: { $0.id == id }) {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 / scale)
            ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
            ctx.stroke(sel.boundingBox.insetBy(dx: -6 / scale, dy: -6 / scale))
        }
        ctx.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEntry()
        let p = imagePoint(event)
        snapshot = document.annotations
        dragStart = p
        lastDragPoint = p
        // A handle wins over every tool, so a text can be resized right after typing it.
        if let corner = handle(at: p), let text = selectedText {
            resizing = (corner, text)
            return
        }
        switch document.tool {
        case .select:
            document.selectedID = document.annotations.last { $0.hitTest(p, tolerance: 6 / scale) }?.id
        case .text:
            beginTextEntry(at: p)
        case .arrow:
            draft = Annotation(kind: .arrow(from: p, to: p), style: document.style)
        case .rect:
            draft = Annotation(kind: .rect(CGRect(origin: p, size: .zero)), style: document.style)
        case .ellipse:
            draft = Annotation(kind: .ellipse(CGRect(origin: p, size: .zero)), style: document.style)
        case .pixelate:
            draft = Annotation(kind: .pixelate(CGRect(origin: p, size: .zero), blockSize: document.pixelateBlockSize), style: document.style)
        case .pen:
            draft = Annotation(kind: .pen([p]), style: document.style)
        case .highlighter:
            draft = Annotation(kind: .highlighter([p]), style: document.style)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        guard let start = dragStart else { return }
        if let resizing {
            let resized = resizing.original.resizingText(corner: resizing.corner, to: p)
            document.setAnnotationsWithoutUndo(document.annotations.map { $0.id == resized.id ? resized : $0 })
            return
        }
        if document.tool == .select {
            guard let id = document.selectedID, let last = lastDragPoint else { return }
            let d = CGVector(dx: p.x - last.x, dy: p.y - last.y)
            document.setAnnotationsWithoutUndo(document.annotations.map { $0.id == id ? $0.translated(by: d) : $0 })
            lastDragPoint = p
            return
        }
        guard var d = draft else { return }
        let frame = SelectionGeometry.rect(from: start, to: p, constrainSquare: event.modifierFlags.contains(.shift))
        switch d.kind {
        case .arrow(let from, _): d.kind = .arrow(from: from, to: p)
        case .rect: d.kind = .rect(frame)
        case .ellipse: d.kind = .ellipse(frame)
        case .pixelate(_, let b): d.kind = .pixelate(frame, blockSize: b)
        case .pen(var pts): pts.append(p); d.kind = .pen(pts)
        case .highlighter(var pts): pts.append(p); d.kind = .highlighter(pts)
        case .text: break
        }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { draft = nil; dragStart = nil; lastDragPoint = nil; resizing = nil; needsDisplay = true }
        if resizing != nil {
            if snapshot != document.annotations {
                let resized = document.annotations
                document.setAnnotationsWithoutUndo(snapshot)
                document.replaceAnnotations(resized, actionName: "Resize")
            }
            return
        }
        if document.tool == .select {
            if document.selectedID != nil, snapshot != document.annotations {
                let moved = document.annotations
                document.setAnnotationsWithoutUndo(snapshot)
                document.replaceAnnotations(moved, actionName: "Move")
            }
            return
        }
        guard let d = draft, isUsable(d) else { return }
        document.add(d)
    }

    private func isUsable(_ a: Annotation) -> Bool {
        switch a.kind {
        case .pen(let pts), .highlighter(let pts): return pts.count >= 2
        case .text: return true
        default:
            let b = a.boundingBox
            return b.width >= 2 || b.height >= 2
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            if document.selectedID != nil { document.removeSelected() } else { super.keyDown(with: event) }
        case 53: // Escape
            commitTextEntry()
            document.selectedID = nil
        default:
            if let ch = event.charactersIgnoringModifiers?.lowercased().first,
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
               let tool = EditorTool.allCases.first(where: { $0.key == ch }) {
                document.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Text entry

    /// Keeps the field being typed in at the current text size and colour.
    private func styleTextField() {
        guard let field = textField else { return }
        let size = document.style.fontSize * scale
        field.font = NSFont.boldSystemFont(ofSize: size)
        field.textColor = NSColor(cgColor: document.style.color.cgColor)
        field.setFrameSize(CGSize(width: max(field.frame.width, 240), height: size * 1.4))
    }

    private func beginTextEntry(at p: CGPoint) {
        // A new text: the size menu must not keep resizing the previous one.
        document.selectedID = nil
        let field = NSTextField(frame: CGRect(origin: viewPoint(p), size: CGSize(width: 240, height: document.style.fontSize * scale * 1.4)))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.boldSystemFont(ofSize: document.style.fontSize * scale)
        field.textColor = NSColor(cgColor: document.style.color.cgColor)
        field.placeholderString = "Text"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOrigin = p
    }

    private func commitTextEntry() {
        guard let field = textField, let origin = textOrigin else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cleared before removal: removing the field ends its editing, which calls
        // back into this method and would otherwise add the text a second time.
        textField = nil
        textOrigin = nil
        field.removeFromSuperview()
        if !string.isEmpty {
            let text = Annotation(kind: .text(origin: origin, string: string), style: document.style)
            document.add(text)
            // Selected straight away, so its resize handles show without switching tools.
            document.selectedID = text.id
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEntry()
            window?.makeFirstResponder(self)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitTextEntry()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEntry()
    }
}
