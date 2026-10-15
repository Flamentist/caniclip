import CoreGraphics
import Foundation

struct RGBAColor: Equatable, Codable {
    var r: Double, g: Double, b: Double, a: Double

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    static let red = RGBAColor(r: 1.0, g: 0.23, b: 0.19, a: 1)
    static let orange = RGBAColor(r: 1.0, g: 0.58, b: 0.0, a: 1)
    static let yellow = RGBAColor(r: 1.0, g: 0.84, b: 0.04, a: 1)
    static let green = RGBAColor(r: 0.2, g: 0.78, b: 0.35, a: 1)
    static let blue = RGBAColor(r: 0.0, g: 0.48, b: 1.0, a: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
}

struct AnnotationStyle: Equatable, Codable {
    var color: RGBAColor = .red
    var strokeWidth: CGFloat = 4
    var fontSize: CGFloat = 24
}

/// One drawn element. Geometry is in image pixels with a top-left origin.
struct Annotation: Identifiable, Equatable, Codable {
    enum Kind: Equatable, Codable {
        case arrow(from: CGPoint, to: CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case pen([CGPoint])
        case highlighter([CGPoint])
        case text(origin: CGPoint, string: String)
        case pixelate(CGRect, blockSize: Int)
    }

    var id: UUID
    var kind: Kind
    var style: AnnotationStyle

    init(id: UUID = UUID(), kind: Kind, style: AnnotationStyle = AnnotationStyle()) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// Highlighter strokes are drawn this many times wider than `strokeWidth`.
    static let highlighterWidthFactor: CGFloat = 4

    /// Rough text extent used for hit testing and selection outlines.
    static func estimatedTextSize(_ string: String, fontSize: CGFloat) -> CGSize {
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        return CGSize(width: max(CGFloat(longest) * fontSize * 0.6, fontSize * 0.6),
                      height: CGFloat(max(lines.count, 1)) * fontSize * 1.2)
    }

    var boundingBox: CGRect {
        switch kind {
        case .arrow(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .rect(let r), .ellipse(let r), .pixelate(let r, _):
            return r
        case .pen(let pts), .highlighter(let pts):
            guard let first = pts.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in pts {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text(let origin, let string):
            return CGRect(origin: origin, size: Self.estimatedTextSize(string, fontSize: style.fontSize))
        }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow(let a, let b):
            return Self.distance(from: p, toSegment: a, b) <= tolerance + style.strokeWidth / 2
        case .rect(let r), .ellipse(let r):
            let outer = r.insetBy(dx: -(tolerance + style.strokeWidth / 2), dy: -(tolerance + style.strokeWidth / 2))
            let inner = r.insetBy(dx: tolerance + style.strokeWidth / 2, dy: tolerance + style.strokeWidth / 2)
            return outer.contains(p) && !(inner.width > 0 && inner.height > 0 && inner.contains(p))
        case .pen(let pts):
            return Self.polylineHit(pts, p, tolerance + style.strokeWidth / 2)
        case .highlighter(let pts):
            return Self.polylineHit(pts, p, tolerance + style.strokeWidth * Self.highlighterWidthFactor / 2)
        case .text, .pixelate:
            return boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    func translated(by d: CGVector) -> Annotation {
        var copy = self
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.dx, y: p.y + d.dy) }
        switch kind {
        case .arrow(let a, let b): copy.kind = .arrow(from: move(a), to: move(b))
        case .rect(let r): copy.kind = .rect(r.offsetBy(dx: d.dx, dy: d.dy))
        case .ellipse(let r): copy.kind = .ellipse(r.offsetBy(dx: d.dx, dy: d.dy))
        case .pen(let pts): copy.kind = .pen(pts.map(move))
        case .highlighter(let pts): copy.kind = .highlighter(pts.map(move))
        case .text(let o, let s): copy.kind = .text(origin: move(o), string: s)
        case .pixelate(let r, let b): copy.kind = .pixelate(r.offsetBy(dx: d.dx, dy: d.dy), blockSize: b)
        }
        return copy
    }

    private static func polylineHit(_ pts: [CGPoint], _ p: CGPoint, _ tol: CGFloat) -> Bool {
        if pts.count == 1 { return hypot(pts[0].x - p.x, pts[0].y - p.y) <= tol }
        for i in 1..<pts.count where distance(from: p, toSegment: pts[i - 1], pts[i]) <= tol {
            return true
        }
        return false
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
