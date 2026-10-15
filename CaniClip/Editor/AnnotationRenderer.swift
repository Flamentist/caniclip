import AppKit

/// Draws annotations into a CGContext whose user space is image pixels with a
/// top-left origin (y grows downward). Used by both the canvas and the exporter.
enum AnnotationRenderer {
    static func draw(_ annotations: [Annotation], in ctx: CGContext, pixelateImage: (Annotation) -> CGImage?) {
        for a in annotations {
            ctx.saveGState()
            ctx.setStrokeColor(a.style.color.cgColor)
            ctx.setFillColor(a.style.color.cgColor)
            ctx.setLineWidth(a.style.strokeWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            switch a.kind {
            case .arrow(let from, let to):
                drawArrow(from: from, to: to, width: a.style.strokeWidth, in: ctx)
            case .rect(let r):
                ctx.stroke(r)
            case .ellipse(let r):
                ctx.strokeEllipse(in: r)
            case .pen(let pts):
                strokePolyline(pts, in: ctx)
            case .highlighter(let pts):
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.4)
                ctx.setLineWidth(a.style.strokeWidth * Annotation.highlighterWidthFactor)
                ctx.setLineCap(.butt)
                strokePolyline(pts, in: ctx)
            case .text(let origin, let string):
                drawText(string, at: origin, style: a.style, in: ctx)
            case .pixelate(let r, _):
                if let img = pixelateImage(a) {
                    // CGImages draw bottom-up; flip locally so the crop lands upright.
                    ctx.translateBy(x: r.minX, y: r.maxY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
                }
            }
            ctx.restoreGState()
        }
    }

    private static func strokePolyline(_ pts: [CGPoint], in ctx: CGContext) {
        guard let first = pts.first else { return }
        if pts.count == 1 {
            ctx.move(to: first)
            ctx.addLine(to: first)
        } else {
            ctx.move(to: first)
            for p in pts.dropFirst() { ctx.addLine(to: p) }
        }
        ctx.strokePath()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, in ctx: CGContext) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let headLength = max(12, width * 4)
        let headHalfWidth = headLength * 0.5
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        ctx.move(to: from)
        ctx.addLine(to: base)
        ctx.strokePath()
        let left = CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth)
        let right = CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth)
        ctx.move(to: to)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: style.fontSize),
            .foregroundColor: NSColor(cgColor: style.color.cgColor) ?? .red,
        ]
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        NSAttributedString(string: string, attributes: attrs).draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
