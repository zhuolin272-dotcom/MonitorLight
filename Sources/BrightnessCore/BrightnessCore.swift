import Foundation

public struct ExternalDisplay: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let systemID: UInt32

    public init(id: String, name: String, systemID: UInt32) {
        self.id = id
        self.name = name
        self.systemID = systemID
    }
}

public enum DisplayParser {
    public static func parse(_ output: String, isBuiltin: (UInt32) -> Bool) -> [ExternalDisplay] {
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^\[\d+\]\s+(.+?)\s+\(([0-9A-Fa-f-]{36})\)\s*$"#) else { return [] }
        let text = output as NSString
        let matches = expression.matches(in: output, range: NSRange(location: 0, length: text.length))
        return matches.enumerated().compactMap { index, match in
            let end = index + 1 < matches.count ? matches[index + 1].range.location : text.length
            let body = text.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
            guard let line = body.components(separatedBy: .newlines).first(where: { $0.contains("- Display ID:") }),
                  let number = line.components(separatedBy: ":").last,
                  let systemID = UInt32(number.trimmingCharacters(in: .whitespaces)), !isBuiltin(systemID) else { return nil }
            return ExternalDisplay(id: text.substring(with: match.range(at: 2)), name: text.substring(with: match.range(at: 1)), systemID: systemID)
        }
    }
}

public struct BrightnessReading: Sendable {
    public let current: Int
    public let maximum: Int

    public init(current: Int, maximum: Int) throws {
        guard maximum > 0, maximum <= 65535, current >= 0, current <= maximum else {
            throw BrightnessError.invalidReply
        }
        self.current = current
        self.maximum = maximum
    }

    public var percent: Int { Int((Double(current) / Double(maximum) * 100).rounded()) }

    public func rawValue(forPercent percent: Double) -> Int {
        let clamped = percent.isFinite ? min(100, max(0, percent)) : 0
        return Int((clamped / 100 * Double(maximum)).rounded())
    }
}

public enum BrightnessError: LocalizedError {
    case invalidReply
    public var errorDescription: String? { "显示器返回的亮度数值无效，请检查 DDC/CI 和连接线。" }
}
