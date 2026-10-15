import Foundation

enum SelectionGeometry {
    /// Drags smaller than this in either dimension are treated as a cancelled click.
    static let minimumSize: CGFloat = 2

    static func rect(from anchor: CGPoint, to current: CGPoint, constrainSquare: Bool) -> CGRect {
        var w = current.x - anchor.x
        var h = current.y - anchor.y
        if constrainSquare {
            let side = max(abs(w), abs(h))
            w = w < 0 ? -side : side
            h = h < 0 ? -side : side
        }
        return CGRect(x: min(anchor.x, anchor.x + w), y: min(anchor.y, anchor.y + h), width: abs(w), height: abs(h))
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSize && rect.height >= minimumSize
    }

    static func sizeLabel(for rect: CGRect, scale: CGFloat) -> String {
        let px = CaptureGeometry.pixelSize(pointSize: rect.size, scale: scale)
        return "\(px.width) × \(px.height)"
    }
}
