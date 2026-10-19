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

    @Published private(set) var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var tool: EditorTool = .arrow
    @Published var style = AnnotationStyle()
    @Published private(set) var isDirty = false
    private(set) var lastSavedURL: URL?

    init(image: CGImage, styleScale: CGFloat = 1) {
        self.image = image
        self.pixelateService = PixelateService(base: image)
        self.styleScale = styleScale
        style.strokeWidth = (style.strokeWidth * styleScale).rounded()
        style.fontSize = (style.fontSize * styleScale).rounded()
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
