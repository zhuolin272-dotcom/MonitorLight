import XCTest
import BrightnessCore
@testable import MonitorLight

final class MonitorModelTests: XCTestCase {
    @MainActor func testBrightnessRequestResetsUncommittedWarmth() throws {
        let model = MonitorModel()
        model.displays = [ExternalDisplay(id: "fake", name: "Test", systemID: 9)]
        model.selectedID = "fake"
        model.reading = try BrightnessReading(current: 45, maximum: 100)
        model.warmth = 1 // Optimistic value whose pending task was superseded.
        model.requestBrightness(50)
        XCTAssertEqual(model.warmth, 0)
        model.selectDisplay("") // Cancel the delayed hardware write.
    }

    @MainActor func testFailedInventoryClearsColorCapability() async throws {
        let model = MonitorModel()
        let gain = try RGBGain(current: 50, maximum: 100)
        model.colorReading = ColorReading(red: gain, green: gain, blue: gain)
        model.refresh() // Test bundle has no bundled DDC helper.
        for _ in 0..<100 where model.isBusy {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.colorReading)
    }
}
