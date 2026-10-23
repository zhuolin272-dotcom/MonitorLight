// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonitorLight",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MonitorLight", targets: ["MonitorLight"])],
    targets: [
        .target(name: "BrightnessCore"),
        .executableTarget(name: "MonitorLight", dependencies: ["BrightnessCore"]),
        .testTarget(name: "BrightnessCoreTests", dependencies: ["BrightnessCore"]),
        .testTarget(name: "MonitorModelTests", dependencies: ["MonitorLight", "BrightnessCore"])
    ]
)
