import SwiftUI

struct PanelView: View {
    @ObservedObject var model: MonitorModel
    private let ink = Color(red: 0.12, green: 0.19, blue: 0.19)
    private let teal = Color(red: 0.08, green: 0.43, blue: 0.37)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(red: 0.8, green: 0.57, blue: 0.22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("屏幕亮度").font(.system(size: 17, weight: .semibold))
                    Text("MONITORLIGHT").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("重新检测显示器").disabled(model.isBusy)
            }

            if model.displays.count > 1 {
                Picker("显示器", selection: Binding(get: { model.selectedID }, set: model.selectDisplay)) {
                    ForEach(model.displays) { display in Text(display.name).tag(display.id) }
                }
                .pickerStyle(.menu)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "display")
                    Text(model.selectedDisplay?.name ?? "外接显示器").fontWeight(.medium)
                    Spacer()
                    if model.isBusy { ProgressView().controlSize(.small) }
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(model.reading == nil ? "—" : "\(Int(model.brightness.rounded()))")
                    .font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                Spacer()
                Text("硬件亮度").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.bottom, -8)

            HStack(spacing: 10) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.brightness }, set: model.requestBrightness), in: 0...100)
                    .tint(teal).disabled(model.reading == nil || model.isBusy)
                    .accessibilityLabel("外接显示器亮度")
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                preset("低亮", symbol: "moon", value: 15)
                preset("日常", symbol: "sun.haze", value: 45)
                preset("明亮", symbol: "sun.max", value: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(model.reading == nil ? Color.orange : teal).frame(width: 5, height: 5)
                    Text(model.status).font(.system(size: 10))
                }.foregroundStyle(.secondary)
                if let error = model.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
            HStack {
                Text("⌘ ⌥ ↑ / ↓  调节 5%").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 340)
        .foregroundStyle(ink)
        .background(Color(red: 0.97, green: 0.97, blue: 0.94))
        .environment(\.colorScheme, .light)
    }

    private func preset(_ title: String, symbol: String, value: Double) -> some View {
        Button { model.requestBrightness(value) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 11, weight: .medium))
                Text("\(Int(value))%").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 11).fill(abs(model.brightness - value) < 1 ? teal.opacity(0.12) : Color.black.opacity(0.035)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.reading == nil || model.isBusy)
    }
}
