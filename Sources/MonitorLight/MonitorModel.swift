import AppKit
import BrightnessCore
import SwiftUI

@MainActor
final class MonitorModel: ObservableObject {
    @Published var displays: [ExternalDisplay] = []
    @Published var selectedID = ""
    @Published var brightness: Double = 0
    @Published var isBusy = false
    @Published var status = "正在检测外接显示器…"
    @Published var error: String?
    @Published var reading: BrightnessReading?
    @Published var colorReading: ColorReading?
    @Published var warmth: Double = 0
    @Published var allowUnverifiedColor = false
    @Published private(set) var colorResponseProfile: ColorResponseProfile?
    @Published var colorMessage = "正在检测硬件冷暖调节…"
    private var originalColor: ColorReading?
    private var confirmedWarmth: Double = 0

    private let client = DDCClient()
    private var pendingWrite: Task<Void, Never>?
    private var needsRefresh = false

    var selectedDisplay: ExternalDisplay? { displays.first { $0.id == selectedID } }
    var canAdjustColor: Bool { colorResponseProfile != nil || allowUnverifiedColor }

    func refresh() {
        guard !isBusy else { needsRefresh = true; return }
        pendingWrite?.cancel()
        pendingWrite = nil
        warmth = confirmedWarmth
        if let reading { brightness = Double(reading.percent) }
        isBusy = true
        error = nil
        Task {
            defer { finishOperation() }
            do {
                let found = try await client.displays()
                displays = found
                if !found.contains(where: { $0.id == selectedID }) {
                    let remembered = UserDefaults.standard.string(forKey: "selectedDisplay")
                    resetColorSelection(found.first(where: { $0.id == remembered })?.id ?? found.first?.id ?? "")
                }
                guard let display = selectedDisplay else {
                    reading = nil
                    colorReading = nil
                    originalColor = nil
                    colorResponseProfile = nil
                    colorMessage = "未检测到外接显示器"
                    status = "未检测到支持的外接显示器"
                    return
                }
                do {
                    let value = try await client.read(display)
                    apply(value)
                    status = "硬件背光 · DDC/CI 已连接"
                } catch {
                    reading = nil
                    self.error = error.localizedDescription
                    status = "无法读取硬件亮度"
                }
                do {
                    colorResponseProfile = ColorResponseProfile.load(displayID: display.id)
                    let color = try await client.readColor(display)
                    colorReading = color
                    let data = UserDefaults.standard.data(forKey: "originalColor.\(display.id)")
                    let saved = data.flatMap { try? JSONDecoder().decode(ColorReading.self, from: $0) }
                    if data != nil && saved == nil {
                        originalColor = nil
                        colorReading = nil
                        colorMessage = "本机原色记录损坏，为避免覆盖原色，已停用调色"
                    } else if let saved, saved.maxima != color.maxima {
                        originalColor = nil
                        colorReading = nil
                        colorMessage = "RGB 范围已变化，请恢复显示器原图像模式后重试"
                    } else {
                        originalColor = saved ?? color
                        if !originalColor!.adjusted(warmth: confirmedWarmth, profile: colorResponseProfile ?? .blueOnlyNormal).matches(color) { confirmedWarmth = 0 }
                        warmth = confirmedWarmth
                        colorMessage = colorResponseProfile == nil ? "RGB 数值可读，实际颜色方向和色温未验证" : "本机方向修正已载入 · 小幅调节，待肉眼复核"
                    }
                } catch {
                    colorReading = nil
                    originalColor = nil
                    colorResponseProfile = nil
                    colorMessage = "当前显示器或 HDR 模式不支持硬件冷暖调节"
                }
            } catch {
                reading = nil
                colorReading = nil
                originalColor = nil
                colorResponseProfile = nil
                displays = []
                selectedID = ""
                colorMessage = "显示器检测失败，硬件冷暖调节不可用"
                self.error = error.localizedDescription
                status = "无法读取硬件亮度"
            }
        }
    }

    func selectDisplay(_ id: String) {
        guard !isBusy else { return }
        resetColorSelection(id)
        UserDefaults.standard.set(id, forKey: "selectedDisplay")
        refresh()
    }

    func resetColorSelection(_ id: String) {
        pendingWrite?.cancel()
        selectedID = id
        reading = nil
        colorReading = nil
        originalColor = nil
        colorResponseProfile = nil
        warmth = 0
        confirmedWarmth = 0
        allowUnverifiedColor = false
    }

    func requestBrightness(_ value: Double) {
        guard let display = selectedDisplay, let baseline = reading, !isBusy else { return }
        warmth = confirmedWarmth
        brightness = min(100, max(0, value))
        let desired = brightness
        pendingWrite?.cancel()
        pendingWrite = Task {
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
                try Task.checkCancellation()
                guard selectedID == display.id else { return }
                isBusy = true
                error = nil
                defer { finishOperation() }
                let value = try await client.set(display, percent: desired, reading: baseline)
                apply(value)
                status = "硬件背光 · 已读回确认"
            } catch is CancellationError {
                return
            } catch {
                brightness = Double(baseline.percent)
                self.error = error.localizedDescription
            }
        }
    }

    func step(_ delta: Double) { requestBrightness(brightness + delta) }

    func requestWarmth(_ value: Double) {
        guard value == 0 || canAdjustColor else {
            colorMessage = "实际颜色方向未验证，请先校验；恢复原色仍可使用"
            return
        }
        guard let display = selectedDisplay, let original = originalColor,
              colorReading != nil, !isBusy else { return }
        if let reading { brightness = Double(reading.percent) }
        let previous = confirmedWarmth
        warmth = value.isFinite ? min(1, max(-1, value)) : 0
        let desired = warmth
        let profile = colorResponseProfile
        pendingWrite?.cancel()
        pendingWrite = Task {
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
                try Task.checkCancellation()
                guard selectedID == display.id else { return }
                guard desired == 0 || canAdjustColor else { warmth = confirmedWarmth; return }
                isBusy = true
                defer { finishOperation() }
                // Persist before the first hardware write. Never overwrite the original.
                let key = "originalColor.\(display.id)"
                if UserDefaults.standard.data(forKey: key) == nil {
                    let data = try JSONEncoder().encode(original)
                    UserDefaults.standard.set(data, forKey: key)
                }
                colorReading = try await client.setColor(display, target: original.adjusted(warmth: desired, profile: profile ?? .blueOnlyNormal))
                confirmedWarmth = desired
                colorMessage = desired == 0 ? "原色 RGB 已恢复并读回；不代表色温已校准" : (profile == nil ? "RGB 数值已读回，实际冷暖方向尚未校准" : "方向修正 RGB 已读回 · 请核对肉眼冷暖，不代表精确色温")
            } catch is CancellationError {
                return
            } catch {
                warmth = previous
                colorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ value: BrightnessReading) {
        reading = value
        brightness = Double(value.percent)
    }

    private func finishOperation() {
        isBusy = false
        if needsRefresh {
            needsRefresh = false
            refresh()
        }
    }
}
