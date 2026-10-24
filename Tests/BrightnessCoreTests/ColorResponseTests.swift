import XCTest
@testable import BrightnessCore

final class ColorResponseTests: XCTestCase {
    func testBlueOnlyCorrectionNeverChangesRedOrGreen() throws {
        let baseline = try color(44, 44, 50)
        XCTAssertEqual(baseline.adjusted(warmth: 1, profile: .blueOnlyNormal).values, [44, 44, 40])
        XCTAssertEqual(baseline.adjusted(warmth: -1, profile: .blueOnlyNormal).values, [44, 44, 60])
        XCTAssertEqual(baseline.adjusted(warmth: 0.5, profile: .blueOnlyNormal).values, [44, 44, 45])
        XCTAssertEqual(baseline.adjusted(warmth: 0, profile: .blueOnlyNormal), baseline)
    }

    func testProfileClampsWithoutTouchingGreenOrMutatingBaseline() throws {
        let baseline = try color(2, 44, 99)
        XCTAssertEqual(baseline.adjusted(warmth: 5, profile: .blueOnlyNormal).values, [2, 44, 89])
        XCTAssertEqual(baseline.adjusted(warmth: -5, profile: .blueOnlyNormal).values, [2, 44, 100])
        XCTAssertEqual(baseline.adjusted(warmth: .nan, profile: .blueOnlyNormal), baseline)
        XCTAssertEqual(baseline.values, [2, 44, 99])
    }

    func testObservationIsScopedToOneDisplayAndInvalidProfilesAreIgnored() {
        let suite = "MonitorLight.ColorResponseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ColorResponseProfile.blueOnlyNormal.rawValue, forKey: "colorResponse.test-screen-A")
        XCTAssertEqual(ColorResponseProfile.load(displayID: "test-screen-A", defaults: defaults), .blueOnlyNormal)
        XCTAssertNil(ColorResponseProfile.load(displayID: "test-screen-B", defaults: defaults))
        defaults.set("inverseRedNormalBlue", forKey: "colorResponse.test-screen-B")
        XCTAssertNil(ColorResponseProfile.load(displayID: "test-screen-B", defaults: defaults))
        defaults.set("unknown", forKey: "colorResponse.test-screen-B")
        XCTAssertNil(ColorResponseProfile.load(displayID: "test-screen-B", defaults: defaults))
    }

    private func color(_ r: Int, _ g: Int, _ b: Int) throws -> ColorReading {
        ColorReading(red: try RGBGain(current: r, maximum: 100),
                     green: try RGBGain(current: g, maximum: 100),
                     blue: try RGBGain(current: b, maximum: 100))
    }
}
