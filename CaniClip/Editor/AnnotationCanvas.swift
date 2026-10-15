import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    let document: EditorDocument

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(document: document)
    }

    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.needsDisplay = true
    }
}
