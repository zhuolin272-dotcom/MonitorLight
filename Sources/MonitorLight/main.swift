import AppKit
import Carbon
import SwiftUI

private let hotkeySignature: OSType = 0x4D4C4954

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MonitorModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.monitorlight.app").count < 2 else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "MonitorLight 屏幕亮度")
        item.button?.toolTip = "MonitorLight · 外接屏硬件亮度"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        registerHotkeys()
        CGDisplayRegisterReconfigurationCallback({ _, _, context in
            guard let context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { delegate.model.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        model.refresh()
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.togglePanel() }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.count > index + 1 {
            let outputPath = CommandLine.arguments[index + 1]
            Task { await self.runSelfTest(outputPath: outputPath) }
        }
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func wake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.model.refresh() }
    }

    private func waitForHardware() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        for _ in 0..<120 {
            if !model.isBusy { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func runSelfTest(outputPath: String) async {
        await waitForHardware()
        guard let original = model.reading else {
            print("SELF_TEST_FAILED: \(model.error ?? model.status)")
            NSApp.terminate(nil)
            return
        }
        let originalPercent = original.percent
        var result: [String: Any] = ["display": model.selectedDisplay?.name ?? "", "originalPercent": originalPercent]
        model.requestBrightness(15)
        await waitForHardware()
        result["preset15Readback"] = model.reading?.percent ?? -1
        model.step(5)
        await waitForHardware()
        result["increaseReadback"] = model.reading?.percent ?? -1
        model.step(-5)
        await waitForHardware()
        result["decreaseReadback"] = model.reading?.percent ?? -1
        if !popover.isShown { togglePanel() }
        await waitForHardware()
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
            }
        }
        model.requestBrightness(Double(originalPercent))
        await waitForHardware()
        result["restoredPercent"] = model.reading?.percent ?? -1
        result["hotkeysRegistered"] = hotkeys.count
        result["error"] = model.error ?? ""
        result["passed"] = (result["preset15Readback"] as? Int == 15) && (result["increaseReadback"] as? Int == 20) && (result["decreaseReadback"] as? Int == 15) && model.reading?.percent == originalPercent && hotkeys.count == 2
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) { print(json) }
        NSApp.terminate(nil)
    }

    private func registerHotkeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard result == noErr, hotkeyID.signature == hotkeySignature else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let delta: Double = hotkeyID.id == 1 ? 5 : -5
            DispatchQueue.main.async { delegate.model.step(delta) }
            return noErr
        }, 1, &event, context, &eventHandler)
        for (id, key) in [(UInt32(1), UInt32(kVK_UpArrow)), (UInt32(2), UInt32(kVK_DownArrow))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(cmdKey | optionKey), EventHotKeyID(signature: hotkeySignature, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotkeys.append(reference) }
            else { model.error = "快捷键被其他软件占用，仍可使用菜单栏滑块。" }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
