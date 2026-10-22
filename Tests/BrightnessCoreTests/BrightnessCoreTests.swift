import XCTest
@testable import BrightnessCore

final class BrightnessCoreTests: XCTestCase {
    func testParsesDetailedInventoryAndExcludesInternalPanel() {
        let inventory = """
        [1] G27M7Pro (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)
         - Product name:  G27M7Pro
         - Display ID:    3
        [2] Unknown Display (BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB)
         - Product name:  Unknown Display
         - Display ID:    1
        """
        let displays = DisplayParser.parse(inventory, isBuiltin: { $0 == 1 })
        XCTAssertEqual(displays.count, 1)
        XCTAssertEqual(displays.first?.name, "G27M7Pro")
        XCTAssertEqual(displays.first?.id, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertEqual(displays.first?.systemID, 3)
    }

    func testParsesSpacesInDisplayNameAndRejectsIncompleteEntries() {
        let inventory = """
        [1] Studio Screen 27 (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)
         - Display ID: 42
        [2] Broken display
        """
        XCTAssertEqual(DisplayParser.parse(inventory, isBuiltin: { _ in false }).first?.name, "Studio Screen 27")
        XCTAssertEqual(DisplayParser.parse("No displays", isBuiltin: { _ in false }).count, 0)
    }

    func testScalesDifferentHardwareRanges() throws {
        let reading = try BrightnessReading(current: 128, maximum: 255)
        XCTAssertEqual(reading.percent, 50)
        XCTAssertEqual(reading.rawValue(forPercent: 80), 204)
        XCTAssertEqual(reading.rawValue(forPercent: -20), 0)
        XCTAssertEqual(reading.rawValue(forPercent: 200), 255)
    }

    func testRejectsMalformedHardwareReplies() {
        XCTAssertThrowsError(try BrightnessReading(current: 5, maximum: 0))
        XCTAssertThrowsError(try BrightnessReading(current: -1, maximum: 100))
        XCTAssertThrowsError(try BrightnessReading(current: 101, maximum: 100))
    }
}
