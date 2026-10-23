import AppKit
import BrightnessCore
import Foundation

enum DDCError: LocalizedError {
    case missingHelper, commandFailed(String), timeout, readbackMismatch(Int, Int)

    var errorDescription: String? {
        switch self {
        case .missingHelper: return "应用内缺少 m1ddc，请使用完整的 MonitorLight.app。"
        case .commandFailed(let detail): return "显示器通信失败：\(detail)"
        case .timeout: return "显示器响应超时，请检查连接或重新检测。"
        case .readbackMismatch(let expected, let actual): return "已发送亮度 \(expected)，读回为 \(actual)。HDR 或显示器模式可能限制调节。"
        }
    }
}

actor DDCClient {
    private let executable: URL

    init() {
        executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc")
    }

    private func command(_ arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw DDCError.missingHelper }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Commands return only a small inventory or an integer, below pipe capacity.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal { throw DDCError.timeout }
            throw DDCError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "DDC/CI 未响应" : String(stderr.prefix(240)))
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func displays() throws -> [ExternalDisplay] {
        let output = try command(["display", "list", "detailed"])
        return DisplayParser.parse(output, isBuiltin: { CGDisplayIsBuiltin($0) != 0 })
    }

    func read(_ display: ExternalDisplay) throws -> BrightnessReading {
        let maximumText = try command(["display", display.id, "max", "luminance"])
        let currentText = try command(["display", display.id, "get", "luminance"])
        guard let maximum = Int(maximumText), let current = Int(currentText) else { throw BrightnessError.invalidReply }
        return try BrightnessReading(current: current, maximum: maximum)
    }

    func readColor(_ display: ExternalDisplay) throws -> ColorReading {
        func channel(_ name: String) throws -> RGBGain {
            let maximumText = try command(["display", display.id, "max", name])
            let currentText = try command(["display", display.id, "get", name])
            guard let maximum = Int(maximumText), let current = Int(currentText) else { throw ColorControlError.invalidReply }
            return try RGBGain(current: current, maximum: maximum)
        }
        return try ColorReading(red: channel("red"), green: channel("green"), blue: channel("blue"))
    }

    func setColor(_ display: ExternalDisplay, target: ColorReading) throws -> ColorReading {
        try ColorTransaction.apply(target: target, read: {
            Thread.sleep(forTimeInterval: 0.18)
            return try readColor(display)
        }, write: { index, value in
            _ = try command(["display", display.id, "set", ["red", "green", "blue"][index], String(value)])
        })
    }

    func set(_ display: ExternalDisplay, percent: Double, reading: BrightnessReading) throws -> BrightnessReading {
        let target = reading.rawValue(forPercent: percent)
        _ = try command(["display", display.id, "set", "luminance", String(target)])
        Thread.sleep(forTimeInterval: 0.18)
        let updated = try read(display)
        guard abs(updated.current - target) <= 1 else { throw DDCError.readbackMismatch(target, updated.current) }
        return updated
    }
}
