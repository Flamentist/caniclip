import AppKit
import Combine

@MainActor
final class EditorDocument: ObservableObject {
    let image: CGImage
    let undoManager = UndoManager()
    let pixelateService: PixelateService
    /// Multiplies the default stroke width and text size, so a large image shown
    /// shrunk in its window still gets annotations that look normal on screen.
    let styleScale: CGFloat
    /// Pixelate block size in image pixels, scaled like strokes so redaction stays coarse.
    var pixelateBlockSize: Int { Int((12 * styleScale).rounded()) }

    @Published private(set) var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var tool: EditorTool = .arrow
    @Published var style = AnnotationStyle()
    @Published private(set) var isDirty = false
    private(set) var lastSavedURL: URL?

    /// `annotations`: edits restored from history; they start clean and not undoable.
    init(image: CGImage, styleScale: CGFloat = 1, annotations: [Annotation] = []) {
        self.image = image
        self.pixelateService = PixelateService(base: image)
        self.styleScale = styleScale
        style.strokeWidth = (style.strokeWidth * styleScale).rounded()
        style.fontSize = (style.fontSize * styleScale).rounded()
        self.annotations = annotations
        undoManager.levelsOfUndo = 100
    }

    func add(_ a: Annotation) {
        replaceAnnotations(annotations + [a], actionName: "Add \(describe(a))")
    }

    /// Replaces the whole list and registers an undo step restoring the old list.
    func replaceAnnotations(_ new: [Annotation], actionName: String) {
        let old = annotations
        guard old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.replaceAnnotations(old, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        annotations = new
        isDirty = true
        pixelateService.evict(keeping: Set(new.map(\.id)))
    }

    /// Live update during a drag; no undo step. Pair with `replaceAnnotations` on mouse up.
    func setAnnotationsWithoutUndo(_ new: [Annotation]) {
        annotations = new
    }

    /// Text sizes offered in the toolbar, before `styleScale`.
    static let textSizes: [CGFloat] = [12, 16, 20, 24, 32, 48, 64, 96]

    /// The selected annotation when it is text.
    var selectedText: Annotation? {
        guard let id = selectedID, let a = annotations.first(where: { $0.id == id }), case .text = a.kind else { return nil }
        return a
    }

    /// The toolbar shows text size instead of stroke width while this is true.
    var isEditingText: Bool { tool == .text || selectedText != nil }

    /// Sets the size for new text and resizes the selected text, if any (undoable).
    func setTextSize(_ size: CGFloat) {
        style.fontSize = size
        guard let text = selectedText, text.style.fontSize != size else { return }
        var resized = text
        resized.style.fontSize = size
        replaceAnnotations(annotations.map { $0.id == text.id ? resized : $0 }, actionName: "Text Size")
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        replaceAnnotations(annotations.filter { $0.id != id }, actionName: "Delete")
        selectedID = nil
    }

    func markSaved(to url: URL) {
        lastSavedURL = url
        isDirty = false
    }

    func rasterize() -> CGImage? {
        ImageComposer.render(base: image, annotations: annotations) { [pixelateService] in
            pixelateService.image(for: $0)
        }
    }

    private func describe(_ a: Annotation) -> String {
        switch a.kind {
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen Stroke"
        case .highlighter: return "Highlight"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
        }
    }
}
