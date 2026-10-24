import XCTest
import CoreGraphics
@testable import BrightnessCore

final class PanelGeometryTests: XCTestCase {
    func testKeepsPopupOnLowerScreenWithNegativeOrigin() {
        let screen = CGRect(x: 159, y: -917, width: 1512, height: 885)
        let frame = CGRect(x: 875, y: -373, width: 366, height: 594)
        let fitted = PanelGeometry.constrained(frame, to: screen)
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertEqual(fitted.maxY, screen.maxY - 8)
        XCTAssertEqual(fitted.size, frame.size)
    }

    func testSmallScreenCapsViewportAndClampsOversizedWindow() {
        let screen = CGRect(x: -800, y: 20, width: 800, height: 400)
        XCTAssertEqual(PanelGeometry.viewportHeight(content: 800, visible: screen.height), 360)
        let fitted = PanelGeometry.constrained(CGRect(x: 0, y: 0, width: 900, height: 800), to: screen)
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertEqual(fitted.width, 784)
        XCTAssertEqual(fitted.height, 384)
    }
}
