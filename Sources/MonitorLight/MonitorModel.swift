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

    private let client = DDCClient()
    private var pendingWrite: Task<Void, Never>?
    private var needsRefresh = false

    var selectedDisplay: ExternalDisplay? { displays.first { $0.id == selectedID } }

    func refresh() {
        guard !isBusy else { needsRefresh = true; return }
        pendingWrite?.cancel()
        pendingWrite = nil
        isBusy = true
        error = nil
        Task {
            defer { finishOperation() }
            do {
                let found = try await client.displays()
                displays = found
                if !found.contains(where: { $0.id == selectedID }) {
                    let remembered = UserDefaults.standard.string(forKey: "selectedDisplay")
                    selectedID = found.first(where: { $0.id == remembered })?.id ?? found.first?.id ?? ""
                }
                guard let display = selectedDisplay else {
                    reading = nil
                    status = "未检测到支持的外接显示器"
                    return
                }
                let value = try await client.read(display)
                apply(value)
                status = "硬件背光 · DDC/CI 已连接"
            } catch {
                reading = nil
                self.error = error.localizedDescription
                status = "无法读取硬件亮度"
            }
        }
    }

    func selectDisplay(_ id: String) {
        pendingWrite?.cancel()
        selectedID = id
        UserDefaults.standard.set(id, forKey: "selectedDisplay")
        reading = nil
        refresh()
    }

    func requestBrightness(_ value: Double) {
        guard let display = selectedDisplay, let baseline = reading, !isBusy else { return }
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
