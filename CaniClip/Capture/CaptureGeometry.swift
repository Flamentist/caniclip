import AppKit

struct DisplayGeometry: Equatable {
    /// `NSScreen.frame`: global coordinates, bottom-left origin, points.
    let frame: CGRect
    /// `NSScreen.backingScaleFactor`.
    let scale: CGFloat
}

enum CaptureGeometry {
    /// ScreenCaptureKit's `sourceRect` is display-local with a top-left origin, in points.
    static func sourceRect(globalRect: CGRect, display: DisplayGeometry) -> CGRect {
        CGRect(
            x: globalRect.minX - display.frame.minX,
            y: display.frame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    static func pixelSize(pointSize: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((pointSize.width * scale).rounded()), Int((pointSize.height * scale).rounded()))
    }

    static func screen(containing point: CGPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? screens.first
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
