import CoreGraphics

enum PanelPlacement {
    /// Origin (global AppKit coordinates) for a panel of `panelSize` sitting just
    /// below `region`, or above it when there is no room, kept inside `visibleFrame`.
    /// A region with no room on either side (a full screen) gets it inside its bottom edge.
    static func origin(panelSize: CGSize, nearRegion region: CGRect, visibleFrame: CGRect, gap: CGFloat) -> CGPoint {
        let margin: CGFloat = 8
        var x = region.midX - panelSize.width / 2
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin)
        var y = region.minY - gap - panelSize.height
        if y < visibleFrame.minY + margin {
            y = region.maxY + gap
            if y + panelSize.height > visibleFrame.maxY - margin {
                y = max(region.minY, visibleFrame.minY) + gap
            }
        }
        return CGPoint(x: x, y: y)
    }
}
