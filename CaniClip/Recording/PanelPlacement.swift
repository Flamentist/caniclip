import CoreGraphics

enum PanelPlacement {
    /// Origin (global AppKit coordinates) for a panel of `panelSize` sitting just
    /// below `region`, or above it when there is no room, kept inside `visibleFrame`.
    static func origin(panelSize: CGSize, nearRegion region: CGRect, visibleFrame: CGRect, gap: CGFloat) -> CGPoint {
        let margin: CGFloat = 8
        var x = region.midX - panelSize.width / 2
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin)
        var y = region.minY - gap - panelSize.height
        if y < visibleFrame.minY + margin {
            y = region.maxY + gap
        }
        return CGPoint(x: x, y: y)
    }
}
