import XCTest
@testable import BrightnessCore

final class ColorTemperatureTests: XCTestCase {
    func testRejectsInvalidChannels() {
        for (value, max) in [(-1, 100), (101, 100), (0, 0), (1, 65536)] {
            XCTAssertThrowsError(try RGBGain(current: value, maximum: max))
        }
    }

    func testWarmCoolAndOriginal() throws {
        let original = try color(80, 70, 60)
        XCTAssertEqual(original.adjusted(warmth: 1).values, [80, 63, 39])
        XCTAssertEqual(original.adjusted(warmth: -1).values, [52, 63, 60])
        XCTAssertEqual(original.adjusted(warmth: 0), original)
        XCTAssertEqual(original.adjusted(warmth: .nan), original)
        XCTAssertEqual(original.adjusted(warmth: 99), original.adjusted(warmth: 1))
    }

    func testRestorationAndDifferentChannelRanges() throws {
        let original = ColorReading(red: try RGBGain(current: 200, maximum: 255),
                                    green: try RGBGain(current: 100, maximum: 200),
                                    blue: try RGBGain(current: 50, maximum: 80))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ColorReading.self, from: data), original)
        XCTAssertEqual(original.adjusted(warmth: 1).values, [200, 90, 33])
        XCTAssertTrue(original.matches(original))
        XCTAssertFalse(original.matches(original.adjusted(warmth: 1)))
        let invalid = Data("{\"current\":-1,\"maximum\":100}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RGBGain.self, from: invalid))
    }

    private func color(_ r: Int, _ g: Int, _ b: Int) throws -> ColorReading {
        ColorReading(red: try RGBGain(current: r, maximum: 100),
                     green: try RGBGain(current: g, maximum: 100),
                     blue: try RGBGain(current: b, maximum: 100))
    }

    func testPartialFailureRollsBackEveryChannel() throws {
        let before = try color(80, 70, 60)
        var actual = before.values
        var attempts = 0
        XCTAssertThrowsError(try ColorTransaction.apply(target: before.adjusted(warmth: 1), read: {
            try self.color(actual[0], actual[1], actual[2])
        }, write: { index, value in
            attempts += 1
            if attempts == 2 { throw ColorControlError.invalidReply }
            actual[index] = value
        })) { error in
            guard case ColorControlError.writeFailed(_, let restored) = error else { return XCTFail("Wrong error") }
            XCTAssertTrue(restored)
        }
        XCTAssertEqual(actual, before.values)
        XCTAssertEqual(attempts, 5)
    }

    func testSuccessfulWriteAndRangeMismatch() throws {
        let before = try color(80, 70, 60)
        let target = before.adjusted(warmth: 1)
        var actual = before.values
        let result = try ColorTransaction.apply(target: target, read: {
            try self.color(actual[0], actual[1], actual[2])
        }, write: { actual[$0] = $1 })
        XCTAssertEqual(result, target)
        let incompatible = ColorReading(red: try RGBGain(current: 80, maximum: 255), green: before.green, blue: before.blue)
        XCTAssertThrowsError(try ColorTransaction.apply(target: incompatible, read: { before }, write: { _, _ in
            XCTFail("Must not write mismatched ranges")
        }))
    }

    func testReadbackMismatchAndRollbackFailureAreReported() throws {
        let before = try color(80, 70, 60)
        var actual = before.values
        var reads = 0
        XCTAssertThrowsError(try ColorTransaction.apply(target: before.adjusted(warmth: 1), read: {
            reads += 1
            if reads == 3 { throw ColorControlError.invalidReply }
            return before // Display silently ignores the write.
        }, write: { index, value in actual[index] = value })) { error in
            guard case ColorControlError.writeFailed(_, let restored) = error else { return XCTFail("Wrong error") }
            XCTAssertFalse(restored)
        }
        XCTAssertEqual(actual, before.values)
    }
}
