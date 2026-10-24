import Foundation

public struct RGBGain: Codable, Equatable, Sendable {
    public let current: Int
    public let maximum: Int

    public init(current: Int, maximum: Int) throws {
        guard (1...65535).contains(maximum), (0...maximum).contains(current) else {
            throw ColorControlError.invalidReply
        }
        self.current = current
        self.maximum = maximum
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(current: values.decode(Int.self, forKey: .current),
                      maximum: values.decode(Int.self, forKey: .maximum))
    }

    fileprivate func scaled(_ factor: Double) -> RGBGain {
        // The factor is internal, finite and within 0...1, so validation cannot fail.
        try! RGBGain(current: Int((Double(current) * factor).rounded()), maximum: maximum)
    }
}

public struct ColorReading: Codable, Equatable, Sendable {
    public let red: RGBGain
    public let green: RGBGain
    public let blue: RGBGain

    public init(red: RGBGain, green: RGBGain, blue: RGBGain) {
        self.red = red; self.green = green; self.blue = blue
    }

    public var values: [Int] { [red.current, green.current, blue.current] }
    public var maxima: [Int] { [red.maximum, green.maximum, blue.maximum] }

    /// Relative tint, not a calibrated Kelvin temperature. Positive is warmer.
    public func adjusted(warmth: Double, profile: ColorResponseProfile? = nil) -> ColorReading {
        let amount = warmth.isFinite ? min(1, max(-1, warmth)) : 0
        if profile == .blueOnlyNormal {
            // Red compensation failed physical validation. Leave red and green at baseline.
            // Blue-only correction remains a limited tint adjustment, not calibrated CCT.
            func shifted(_ gain: RGBGain) -> RGBGain {
                let value = min(Double(gain.maximum), max(0, Double(gain.current) - Double(gain.maximum) * 0.10 * amount))
                return try! RGBGain(current: Int(value.rounded()), maximum: gain.maximum)
            }
            return ColorReading(red: red, green: green, blue: shifted(blue))
        }
        return ColorReading(red: red.scaled(amount < 0 ? 1 + 0.35 * amount : 1),
                            green: green.scaled(1 - 0.1 * abs(amount)),
                            blue: blue.scaled(amount > 0 ? 1 - 0.35 * amount : 1))
    }

    public func matches(_ other: ColorReading) -> Bool {
        maxima == other.maxima && zip(values, other.values).allSatisfy { abs($0 - $1) <= 1 }
    }
}

public enum ColorControlError: LocalizedError {
    case invalidReply
    case readbackMismatch(expected: [Int], actual: [Int])
    case writeFailed(String, restored: Bool)

    public var errorDescription: String? {
        switch self {
        case .invalidReply: return "RGB 返回值无效，当前显示器或图像模式可能不支持冷暖调节。"
        case .readbackMismatch(let expected, let actual): return "RGB 目标 \(expected)，读回 \(actual)，当前图像模式可能限制调色"
        case .writeFailed(let detail, let restored):
            return "冷暖调节失败：\(detail)。" + (restored ? "已恢复操作前颜色。" : "未能确认恢复，请通过显示器菜单检查 RGB，或重试恢复原色。")
        }
    }
}
