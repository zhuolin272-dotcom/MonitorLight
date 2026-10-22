import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
    let gold = NSColor(calibratedRed: 0.96, green: 0.77, blue: 0.39, alpha: 1)
    gold.setFill()
    NSBezierPath(ovalIn: NSRect(x: 342, y: 342, width: 340, height: 340)).fill()
    gold.setStroke()
    for index in 0..<8 {
        let angle = Double(index) * Double.pi / 4
        let path = NSBezierPath()
        path.lineWidth = 35
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 512 + cos(angle) * 255, y: 512 + sin(angle) * 255))
        path.line(to: NSPoint(x: 512 + cos(angle) * 338, y: 512 + sin(angle) * 338))
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
