import Foundation
import CoreGraphics

public enum PanelGeometry {
    public static func viewportHeight(content: CGFloat, visible: CGFloat) -> CGFloat {
        min(max(1, content), max(1, visible - 40))
    }

    public static func constrained(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let area = visible.insetBy(dx: 8, dy: 8)
        let width = min(frame.width, max(1, area.width))
        let height = min(frame.height, max(1, area.height))
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - width),
                      y: min(max(frame.minY, area.minY), area.maxY - height),
                      width: width, height: height)
    }
}
